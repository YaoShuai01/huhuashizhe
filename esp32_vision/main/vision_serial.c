/**
 * vision_serial - 串口图传（ESP32-S3 原生 USB-Serial-JTAG）
 *
 * 用途：一根 USB 线直连电脑，无需任何网络即可看实时画面。
 * 说明：原实现走 UART0(CH343 口)，实测该口未接到 UART0 引脚；
 *       改为走原生 USB 口后，插 OTG 口即可同时看日志与画面。
 *       推流期间自动静默日志，避免污染二进制流。
 *
 * 协议（帧）：'H''V' + type + len32(LE) + JPEG数据
 *   type 0x03 = 实时流帧；type 0x04 = 高清拍照
 *
 * 命令（文本行）：
 *   VSS  开始实时流：回 "VOK SS" → 持续发 0x03 帧
 *   VSE  停止：回 "VOK SE"
 *   VS1  500万像素拍照(QSXGA)：需先 VSS，回 0x04 帧
 */
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "driver/usb_serial_jtag.h"
#include "vision_serial.h"
#include "vision_cam.h"
#include "vision_wifi.h"

#define VS_TX_BUF       16384
#define VS_RX_BUF       1024
#define VS_WRITE_CHUNK  4096    // 单次写入上限：必须小于 TX 环形缓冲区，否则整块被拒

static bool s_streaming = false;
static int  s_vflip = 0;       // 垂直翻转（画面上下颠倒时打开）
static int  s_hmirror = 0;     // 水平翻转（画面左右镜像时打开）

// 推流采集参数（可由 VRES / VQ 命令实时调整）
#define VS_STREAM_RES   3      // 默认 HD 1280x720
#define VS_STREAM_FPS   10
#define VS_STREAM_Q     12
#define VS_RES_MAX      5      // 推流封顶 UXGA 1600x1200（更高会掉到 1fps 以下）

static int s_res = VS_STREAM_RES;
static int s_q   = VS_STREAM_Q;

static int s_saved_res = -1;
static int s_saved_fps = 0;
static int s_saved_q   = 0;

static const char *k_ack_ss = "VOK SS 3000000\n";
static const char *k_ack_se = "VOK SE 115200\n";
static const char *k_err_need = "VERR need VSS first\n";

static int vs_write(const char *s, int len)
{
    int sent = 0;
    while (sent < len) {
        int chunk = len - sent;
        if (chunk > VS_WRITE_CHUNK) chunk = VS_WRITE_CHUNK;
        int n = usb_serial_jtag_write_bytes(s + sent, chunk, pdMS_TO_TICKS(1000));
        if (n <= 0) break;
        sent += n;
    }
    return sent;
}

static void vs_send_frame(uint8_t type, camera_fb_t *fb)
{
    uint8_t hdr[8] = {
        'H', 'V', type,
        (uint8_t)(fb->len), (uint8_t)(fb->len >> 8),
        (uint8_t)(fb->len >> 16), (uint8_t)(fb->len >> 24), 0
    };
    if (vs_write((const char *)hdr, 8) != 8) return;
    vs_write((const char *)fb->buf, (int)fb->len);
}

static void vs_enter_stream(void)
{
    if (s_streaming) return;

    // 先静默日志，再回执，避免日志字节混进数据流
    esp_log_level_set("*", ESP_LOG_NONE);
    vTaskDelay(pdMS_TO_TICKS(50));

    // 套用当前选择的采集参数（原参数退出时恢复）
    s_saved_res = cam_get_stream_res();
    s_saved_fps = cam_get_fps();
    s_saved_q   = cam_get_quality();
    cam_set_stream_res(s_res);
    cam_set_stream_params(VS_STREAM_FPS, s_q);
    vTaskDelay(pdMS_TO_TICKS(200));

    vs_write(k_ack_ss, strlen(k_ack_ss));
    s_streaming = true;
}

static void vs_exit_stream(void)
{
    if (!s_streaming) return;
    s_streaming = false;

    vs_write(k_ack_se, strlen(k_ack_se));

    if (s_saved_res >= 0) {
        cam_set_stream_res(s_saved_res);
        cam_set_stream_params(s_saved_fps, s_saved_q);
        s_saved_res = -1;
    }
    esp_log_level_set("*", ESP_LOG_INFO);
}

static void vs_snapshot(int res_idx)
{
    if (!s_streaming) {
        vs_write(k_err_need, strlen(k_err_need));
        return;
    }
    if (res_idx < 0 || res_idx >= 8) res_idx = 5;

    int saved = cam_get_stream_res();
    cam_set_snapshot_res(res_idx);      // 不夹取，允许 QSXGA 5MP
    vTaskDelay(pdMS_TO_TICKS(300));

    char msg[48];
    int ml = snprintf(msg, sizeof(msg), "SNAP begin res=%d\n", res_idx);
    vs_write(msg, ml);

    // 切换分辨率后缓冲里还残留旧尺寸帧，先丢弃，否则会拍到上一档的画面
    for (int i = 0; i < 3; i++) {
        camera_fb_t *old = cam_capture();
        if (old) cam_release(old);
        vTaskDelay(pdMS_TO_TICKS(80));
    }

    camera_fb_t *fb = NULL;
    for (int tries = 0; tries < 10; tries++) {
        fb = cam_capture();
        if (fb) {
            // 尺寸不符说明还是旧帧，丢掉重取（QSXGA 至少 2000 宽，UXGA 至少 1500）
            int min_w = (res_idx >= 6) ? 2000 : (res_idx == 5 ? 1500 : 0);
            if (fb->width >= min_w) break;
            cam_release(fb);
            fb = NULL;
        }
        vTaskDelay(pdMS_TO_TICKS(150));
    }
    if (!fb) {
        ml = snprintf(msg, sizeof(msg), "SNAP null res=%d\n", res_idx);
        vs_write(msg, ml);
        cam_set_stream_res(saved);
        return;
    }
    unsigned flen = (unsigned)fb->len;
    vs_send_frame(0x04, fb);
    cam_release(fb);
    ml = snprintf(msg, sizeof(msg), "SNAP ok len=%u\n", flen);
    vs_write(msg, ml);
    cam_set_stream_res(saved);
}

static void vs_handle_line(const char *line, int len)
{
    if (len <= 0) return;
    char msg[48];
    if (!strncmp(line, "VSS", 3)) {
        vs_enter_stream();
    } else if (!strncmp(line, "VSE", 3)) {
        vs_exit_stream();
    } else if (!strncmp(line, "VS1", 3)) {
        vs_snapshot(5);    // UXGA 1600x1200
    } else if (!strncmp(line, "VS2", 3)) {
        vs_snapshot(7);    // QSXGA 2560x1920（500万像素）
    } else if (!strncmp(line, "VFLIP", 5)) {
        s_vflip = (len > 6 && line[6] == '1') ? 1 : 0;
        cam_set_vflip(s_vflip);
        if (!s_streaming) {     // 推流中不回执，避免字节混进画面数据
            int ml = snprintf(msg, sizeof(msg), "VOK FLIP v=%d h=%d\n", s_vflip, s_hmirror);
            vs_write(msg, ml);
        }
    } else if (!strncmp(line, "HMIRROR", 7)) {
        s_hmirror = (len > 8 && line[8] == '1') ? 1 : 0;
        cam_set_hmirror(s_hmirror);
        if (!s_streaming) {
            int ml = snprintf(msg, sizeof(msg), "VOK FLIP v=%d h=%d\n", s_vflip, s_hmirror);
            vs_write(msg, ml);
        }
    } else if (!strncmp(line, "VRES", 4)) {
        int idx = atoi(line + 5);              // "VRES 3"
        if (idx < 0) idx = 0;
        if (idx > VS_RES_MAX) idx = VS_RES_MAX;
        s_res = idx;
        if (s_streaming) {
            cam_set_stream_res(s_res);
        } else {
            int ml = snprintf(msg, sizeof(msg), "VOK RES %d\n", s_res);
            vs_write(msg, ml);
        }
    } else if (!strncmp(line, "VQ", 2)) {
        int q = atoi(line + 3);                // "VQ 10"
        if (q < 6) q = 6;
        if (q > 25) q = 25;
        s_q = q;
        if (s_streaming) {
            cam_set_stream_params(VS_STREAM_FPS, s_q);
        } else {
            int ml = snprintf(msg, sizeof(msg), "VOK Q %d\n", s_q);
            vs_write(msg, ml);
        }
    } else if (!strncmp(line, "VBW", 3)) {
        // 诊断：切换 20/40MHz，对比空口吞吐
        int ht40 = (len > 4 && line[4] == '4');
        esp_err_t e = esp_wifi_set_bandwidth(WIFI_IF_STA, ht40 ? WIFI_BW_HT40 : WIFI_BW_HT20);
        int ml = snprintf(msg, sizeof(msg), "VOK BW %s %s\n",
                          ht40 ? "HT40" : "HT20", (e == ESP_OK) ? "ok" : "err");
        vs_write(msg, ml);
    } else if (!strncmp(line, "VAP", 3)) {
        // 诊断：开/关自带热点，验证 AP+STA 共存是否拖慢吞吐
        int on = (len > 4 && line[4] == '1');
        esp_err_t e = esp_wifi_set_mode(on ? WIFI_MODE_APSTA : WIFI_MODE_STA);
        int ml = snprintf(msg, sizeof(msg), "VOK AP %d %s\n",
                          on, (e == ESP_OK) ? "ok" : "err");
        vs_write(msg, ml);
    } else if (!strncmp(line, "VWIFI", 5)) {
        // 运行时切换 STA 目标：VWIFI <ssid> <password>
        if (len > 6 && line[5] == ' ') {
            char buf[96];
            strlcpy(buf, line, sizeof(buf));
            char *ssid = buf + 6;
            char *pass = strchr(ssid, ' ');
            if (pass != NULL) { *pass = '\0'; pass++; }
            esp_err_t e = vision_wifi_set_sta(ssid, pass);
            int ml = snprintf(msg, sizeof(msg), "VOK WIFI %s\n",
                              (e == ESP_OK) ? "ok" : "err");
            vs_write(msg, ml);
        }
    }
}

static void serial_task(void *pv)
{
    char line[96];
    int llen = 0;
    uint8_t buf[128];

    while (1) {
        int n = usb_serial_jtag_read_bytes(buf, sizeof(buf), pdMS_TO_TICKS(20));
        if (n > 0) {
            for (int i = 0; i < n; i++) {
                if (buf[i] == '\n' || buf[i] == '\r') {
                    line[llen] = '\0';
                    vs_handle_line(line, llen);
                    llen = 0;
                } else if (llen < (int)sizeof(line) - 1) {
                    line[llen++] = (char)buf[i];
                }
            }
        }
        if (s_streaming) {
            camera_fb_t *fb = cam_capture();
            if (fb) {
                vs_send_frame(0x03, fb);
                cam_release(fb);
            } else {
                vTaskDelay(pdMS_TO_TICKS(50));
            }
        }
    }
}

esp_err_t vision_serial_start(void)
{
    usb_serial_jtag_driver_config_t cfg = {
        .tx_buffer_size = VS_TX_BUF,
        .rx_buffer_size = VS_RX_BUF,
    };
    esp_err_t err = usb_serial_jtag_driver_install(&cfg);
    if (err != ESP_OK) {
        ESP_LOGE("VSER", "USB-Serial-JTAG 驱动安装失败: %s", esp_err_to_name(err));
        return err;
    }

    if (xTaskCreate(serial_task, "vserial", 6144, NULL, 5, NULL) != pdPASS) {
        return ESP_FAIL;
    }
    return ESP_OK;
}
