/**
 * vision_udp - UDP 服务实现（命令解析 + 推流任务 + 分段发送）
 */
#include <string.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_psram.h"
#include "lwip/sockets.h"

#include "vision_udp.h"
#include "vision_cam.h"
#include "vision_wifi.h"

static const char *TAG = "VUDP";

#define SEG_MAX        1400    // 单段payload上限（≤MTU，避免IP分片：
                               // 48KB大包要切30+个IP分片，任一分片丢失整帧皆失）
#define RX_BUF_SIZE    128
#define SEND_FLAG_START 0x01

enum { FRAME_TYPE_STREAM = 0x01, FRAME_TYPE_SNAPSHOT = 0x02 };

static int  s_sock = -1;
static struct sockaddr_in s_client;      // 最近命令来源
static bool s_has_client = false;

static volatile bool s_streaming = false;
static uint32_t s_frame_seq = 0;
static uint32_t s_photo_id = 0;

// ==================== 分段发送 ====================
// FEC：每 FEC_GROUP 个数据段生成 1 个 XOR 校验段，
// 接收端丢 1 个分段时可用校验段恢复该帧，避免"丢一段废一帧"——
// 720p一帧约65段，1%丢包时整帧成功率仅52%；加FEC后可达95%以上。
#define FEC_GROUP      8
#define FEC_FLAG       0x02    // flags bit1：本包是FEC校验段

static int send_segments(int type, uint32_t photo_id, const uint8_t *jpg, uint32_t total)
{
    if (!s_has_client) return -1;

    const uint16_t seg_cnt = (uint16_t)((total + SEG_MAX - 1) / SEG_MAX);
    uint8_t buf[22 + SEG_MAX];
    uint8_t fec_acc[SEG_MAX];
    int fec_in_group = 0;
    uint16_t fec_group = 0;
    memset(fec_acc, 0, SEG_MAX);

    for (uint16_t seg = 0; seg < seg_cnt; seg++) {
        // ★ 必须是 uint32：UXGA一帧约200KB，uint16在第47段就会回绕，
        //   导致后续分段全部重复发送文件开头的数据，画面大面积花屏
        uint32_t off = (uint32_t)seg * SEG_MAX;
        uint16_t seg_len = (uint16_t)((total - off) > SEG_MAX ? SEG_MAX : (total - off));

        buf[0] = 'H'; buf[1] = 'V';
        buf[2] = (uint8_t)type;
        buf[3] = (seg == 0) ? SEND_FLAG_START : 0;
        buf[4]  = (uint8_t)(photo_id);
        buf[5]  = (uint8_t)(photo_id >> 8);
        buf[6]  = (uint8_t)(photo_id >> 16);
        buf[7]  = (uint8_t)(photo_id >> 24);
        uint32_t seq = s_frame_seq;
        buf[8]  = (uint8_t)(seq);
        buf[9]  = (uint8_t)(seq >> 8);
        buf[10] = (uint8_t)(seq >> 16);
        buf[11] = (uint8_t)(seq >> 24);
        buf[12] = (uint8_t)(seg);
        buf[13] = (uint8_t)(seg >> 8);
        buf[14] = (uint8_t)(seg_cnt);
        buf[15] = (uint8_t)(seg_cnt >> 8);
        buf[16] = (uint8_t)(total);
        buf[17] = (uint8_t)(total >> 8);
        buf[18] = (uint8_t)(total >> 16);
        buf[19] = (uint8_t)(total >> 24);
        buf[20] = (uint8_t)(seg_len);
        buf[21] = (uint8_t)(seg_len >> 8);
        memcpy(buf + 22, jpg + off, seg_len);

        int sent = sendto(s_sock, buf, 22 + seg_len, 0,
                          (struct sockaddr *)&s_client, sizeof(s_client));
        if (sent < 0) {
            ESP_LOGW(TAG, "sendto 失败 errno=%d", errno);
            return -1;
        }

        // 累积本组 XOR
        if (fec_in_group == 0) memset(fec_acc, 0, SEG_MAX);
        for (uint16_t i = 0; i < seg_len; i++) fec_acc[i] ^= jpg[off + i];
        fec_in_group++;

        // 组满或到达最后一帧：发送校验段（固定SEG_MAX长，短段按零补齐）
        if (fec_in_group == FEC_GROUP || seg == seg_cnt - 1) {
            buf[3] = FEC_FLAG;
            buf[12] = (uint8_t)(fec_group);
            buf[13] = (uint8_t)(fec_group >> 8);
            buf[20] = (uint8_t)(SEG_MAX);
            buf[21] = (uint8_t)(SEG_MAX >> 8);
            memcpy(buf + 22, fec_acc, SEG_MAX);
            sendto(s_sock, buf, 22 + SEG_MAX, 0,
                   (struct sockaddr *)&s_client, sizeof(s_client));
            fec_group++;
            fec_in_group = 0;
        }
    }
    s_frame_seq++;
    return 0;
}

// ==================== 采集/发送流水线 ====================
// 采集与发送拆成两个任务：采集完立即把帧投递到队列去采下一帧，
// 发送任务并行把上一帧发出去。
// 原来单任务串行"采集→发完几十个包→再采集"，发送耗时全部串进帧周期，
// 是实际帧率只有设定值一半左右的核心原因。
#define FB_QUEUE_LEN 2
static QueueHandle_t s_fb_q = NULL;

static void capture_task(void *pv)
{
    while (1) {
        if (!s_streaming || !s_has_client) {
            vTaskDelay(pdMS_TO_TICKS(50));
            continue;
        }

        int64_t t0 = esp_timer_get_time();
        camera_fb_t *fb = cam_capture();
        if (!fb) {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        // 队列满说明网络发不出去：直接丢这帧，避免延迟越积越大
        if (xQueueSend(s_fb_q, &fb, 0) != pdTRUE) {
            cam_release(fb);
        }

        // 按 fps 定拍，采集耗时计入间隔
        int interval_ms = 1000 / cam_get_fps();
        int elapsed_ms = (int)((esp_timer_get_time() - t0) / 1000);
        int remain = interval_ms - elapsed_ms;
        if (remain > 0) vTaskDelay(pdMS_TO_TICKS(remain));
    }
}

static void send_task(void *pv)
{
    camera_fb_t *fb = NULL;
    while (1) {
        if (xQueueReceive(s_fb_q, &fb, pdMS_TO_TICKS(200)) == pdTRUE && fb) {
            send_segments(FRAME_TYPE_STREAM, 0, fb->buf, fb->len);
            cam_release(fb);
            fb = NULL;
        }
    }
}

/// 清空待发送队列，把帧缓冲立即还给摄像头（拍照/切档前调用）
static void drain_fb_queue(void)
{
    camera_fb_t *stale = NULL;
    while (s_fb_q && xQueueReceive(s_fb_q, &stale, 0) == pdTRUE) {
        if (stale) cam_release(stale);
        stale = NULL;
    }
}

// ==================== 命令处理 ====================
static void send_text(const char *msg)
{
    if (!s_has_client) return;
    sendto(s_sock, msg, strlen(msg), 0,
           (struct sockaddr *)&s_client, sizeof(s_client));
}

static void do_snapshot(int res_idx)
{
    if (res_idx < 0 || res_idx >= k_cam_res_count) res_idx = 7;   // 默认5MP

    int saved_res = cam_get_stream_res();
    bool was_streaming = s_streaming;
    s_streaming = false;                    // 拍照期间暂停推流，释放帧缓冲

    vTaskDelay(pdMS_TO_TICKS(150));         // 等上一帧归还
    drain_fb_queue();                       // 丢弃队列里未发的帧，腾出帧缓冲
    cam_set_stream_res(res_idx);

    int64_t t0 = esp_timer_get_time();
    camera_fb_t *fb = cam_capture();
    if (!fb) {
        send_text("VERR SNAPSHOT_FAIL");
        cam_set_stream_res(saved_res);
        s_streaming = was_streaming;
        return;
    }

    uint32_t id = ++s_photo_id;
    ESP_LOGI(TAG, "拍照 %s %u字节 (%.1fMB) 耗时%dms",
             k_cam_res[res_idx].name, (unsigned)fb->len, fb->len / 1048576.0,
             (int)((esp_timer_get_time() - t0) / 1000));

    int rc = send_segments(FRAME_TYPE_SNAPSHOT, id, fb->buf, fb->len);
    cam_release(fb);

    cam_set_stream_res(saved_res);          // 恢复推流分辨率
    s_streaming = was_streaming;

    char ack[64];
    snprintf(ack, sizeof(ack), "VOK SNAP id=%u res=%s rc=%d",
             (unsigned)id, k_cam_res[res_idx].name, rc);
    send_text(ack);
}

static void handle_command(char *cmd, int len)
{
    cmd[len] = '\0';
    ESP_LOGI(TAG, "命令: %s", cmd);

    char ack[160];

    if (!strncmp(cmd, "VSTART", 6)) {
        int res = 2, fps = 12, q = 12;
        int n = sscanf(cmd, "VSTART %d %d %d", &res, &fps, &q);
        if (n >= 1) {
            if (res < 0 || res >= k_cam_res_count) res = 2;
            if (fps < 2 || fps > 30) fps = 12;   // 上限30fps（VGA/XGA可跑到）
            if (q < 6 || q > 25) q = 12;
        }
        // 切分辨率会重启传感器PLL：先停采、清空队列，再改配置
        s_streaming = false;
        vTaskDelay(pdMS_TO_TICKS(80));
        drain_fb_queue();
        cam_set_stream_res(res);
        cam_set_stream_params(fps, q);
        s_streaming = true;
        snprintf(ack, sizeof(ack), "VOK STREAM %s %dfps q%d",
                 k_cam_res[res].name, fps, q);
        send_text(ack);

    } else if (!strncmp(cmd, "VSTOP", 5)) {
        s_streaming = false;
        send_text("VOK STOP");

    } else if (!strncmp(cmd, "VSNAP", 5)) {
        int res = 7;
        sscanf(cmd, "VSNAP %d", &res);
        do_snapshot(res);

    } else if (!strncmp(cmd, "VINFO", 5)) {
        snprintf(ack, sizeof(ack),
                 "VOK INFO sensor=%s res=%s fps=%d q=%d streaming=%d ip=%s psram=%dKB",
                 cam_sensor_name(),
                 k_cam_res[cam_get_stream_res()].name,
                 cam_get_fps(), cam_get_quality(),
                 (int)s_streaming, vision_wifi_ip_str(),
                 (int)(esp_psram_get_size() / 1024));
        send_text(ack);

    } else if (!strncmp(cmd, "VSET", 4)) {
        int fps = 0, q = 0;
        sscanf(cmd, "VSET %d %d", &fps, &q);
        cam_set_stream_params(fps, q);
        snprintf(ack, sizeof(ack), "VOK SET %dfps q%d",
                 cam_get_fps(), cam_get_quality());
        send_text(ack);

    } else if (!strncmp(cmd, "VFLIP", 5)) {
        int on = 0;
        sscanf(cmd, "VFLIP %d", &on);
        cam_set_vflip(on);
        send_text(on ? "VOK FLIP 1" : "VOK FLIP 0");

    } else if (!strncmp(cmd, "VMIR", 4)) {
        int on = 0;
        sscanf(cmd, "VMIR %d", &on);
        cam_set_hmirror(on);
        send_text(on ? "VOK MIR 1" : "VOK MIR 0");

    } else {
        send_text("VERR UNKNOWN_CMD");
    }
}

// ==================== UDP 服务任务 ====================
static void udp_server_task(void *pv)
{
    uint8_t rx[RX_BUF_SIZE];
    struct sockaddr_in addr = { 0 };
    socklen_t addr_len = sizeof(addr);

    s_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (s_sock < 0) {
        ESP_LOGE(TAG, "socket 创建失败 errno=%d", errno);
        vTaskDelete(NULL);
        return;
    }

    struct timeval tv = { .tv_sec = 0, .tv_usec = 500000 };
    setsockopt(s_sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    // 提高发送缓冲，保证48000字节分段能发出
    int sndbuf = 128 * 1024;
    setsockopt(s_sock, SOL_SOCKET, SO_SNDBUF, &sndbuf, sizeof(sndbuf));

    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(VISION_UDP_PORT);
    if (bind(s_sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        ESP_LOGE(TAG, "bind %d 失败 errno=%d", VISION_UDP_PORT, errno);
        close(s_sock);
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(TAG, "图传服务就绪，端口 %d，等待手机指令...", VISION_UDP_PORT);

    while (1) {
        int len = recvfrom(s_sock, rx, RX_BUF_SIZE - 1, 0,
                           (struct sockaddr *)&s_client, &addr_len);
        if (len <= 0) continue;
        s_has_client = true;
        handle_command((char *)rx, len);
    }
}

esp_err_t vision_udp_start(void)
{
    s_fb_q = xQueueCreate(FB_QUEUE_LEN, sizeof(camera_fb_t *));
    if (!s_fb_q) {
        ESP_LOGE(TAG, "帧队列创建失败");
        return ESP_FAIL;
    }

    // 采集固定核1（JPEG编码吃CPU），发送固定核0（贴近WiFi任务），双核并行
    if (xTaskCreatePinnedToCore(capture_task, "vcapture", 4096, NULL, 5, NULL, 1) != pdPASS ||
        xTaskCreatePinnedToCore(send_task, "vsend", 8192, NULL, 6, NULL, 0) != pdPASS ||
        xTaskCreate(udp_server_task, "vudp", 8192, NULL, 5, NULL) != pdPASS) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

bool vision_udp_streaming(void)
{
    return s_streaming;
}

bool vision_udp_set_streaming(bool on)
{
    bool old = s_streaming;
    s_streaming = on;
    return old;
}
