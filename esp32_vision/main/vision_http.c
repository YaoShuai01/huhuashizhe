/**
 * vision_http - MJPEG 浏览器图传实现
 */
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "lwip/sockets.h"

#include "vision_http.h"
#include "vision_cam.h"
#include "vision_udp.h"

static const char *TAG = "VHTTP";

#define HTTP_PORT      80
#define BUF_SIZE       1024
#define STREAM_CLIENTS_MAX 1

static volatile int s_stream_clients = 0;

// ==================== 通用发送 ====================
static int send_all(int sock, const char *buf, size_t len)
{
    size_t sent = 0;
    while (sent < len) {
        int n = send(sock, buf + sent, len - sent, 0);
        if (n <= 0) return -1;
        sent += n;
    }
    return 0;
}

static void send_text_response(int sock, const char *body)
{
    char header[128];
    int hl = snprintf(header, sizeof(header),
                      "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\n"
                      "Content-Length: %d\r\nConnection: close\r\n\r\n",
                      (int)strlen(body));
    send_all(sock, header, hl);
    send_all(sock, body, strlen(body));
}

// ==================== 体验主页 ====================
static const char k_index_html[] =
"<!DOCTYPE html><html><head><meta charset='utf-8'>"
"<meta name='viewport' content='width=device-width,initial-scale=1'>"
"<title>护花使者图传</title><style>"
"body{font-family:system-ui;background:#111;color:#eee;margin:0;padding:12px;text-align:center}"
"img{width:100%;max-width:720px;border-radius:8px;background:#222}"
"a.btn{display:inline-block;margin:8px 6px;padding:10px 18px;background:#5b6cff;color:#fff;"
"border-radius:8px;text-decoration:none;font-size:15px}"
"p{color:#999;font-size:13px;margin:6px 0}"
"#st{font-family:ui-monospace,monospace;font-size:14px;color:#7fe;background:#1a1a1a;"
"padding:8px;border-radius:6px;margin:8px 0}"
".warn{color:#f96!important}"
"</style></head><body>"
"<h3>护花使者 · 视觉板预览</h3>"
"<div id='st'>读取状态中…</div>"
"<img src='/stream' alt='等待画面...'>"
"<div>"
"<a class='btn' href='/capture'>拍 5MP 照片 (2560×1920)</a>"
"<a class='btn' href='/capture?res=3'>拍 720p 快照</a>"
"</div>"
"<p>本页预览为 VGA @5fps，仅供快速观察，不代表实际图传画质。</p>"
"<p>正式图传走 UDP 8889（HD 1280×720 @20fps，画质随画面复杂度自动调整以保帧率）。</p>"
"<p>用 PC 端验收脚本才能看到真实的帧率与码率。</p>"
"<script>"
"async function tick(){"
"try{"
"const r=await fetch('/status',{cache:'no-store'});const s=await r.json();"
"let t=s.res+' '+s.fps+'fps q'+s.q;"
"if(s.qbase>0&&s.q>s.qbase)t+=' ↓自适应(基准q'+s.qbase+')';"
"t+=' | 均帧'+s.avg_kb+'KB 末帧'+s.last_kb+'KB';"
"t+=' | 队列'+s.queue+'/2 丢'+s.dropped;"
"t+=' | 累计'+s.frames_total+'帧';"
"t+=s.streaming?' | 推流中':' | 已停止';"
"const d=document.getElementById('st');"
"d.textContent=t;"
"d.className=(s.q>s.qbase&&s.qbase>0)?'warn':'';"
"}catch(e){document.getElementById('st').textContent='状态读取失败';}"
"}"
"tick();setInterval(tick,2000);"
"</script>"
"</body></html>";

// ==================== 状态查询（供页面轮询 / 验收脚本）====================
static void handle_status(int sock)
{
    vision_udp_stats_t st;
    vision_udp_get_stats(&st);

    // 分辨率名从 k_cam_res 表取；越界时给个安全值避免数组越界
    const char *res_name = (st.res_idx >= 0 && st.res_idx < k_cam_res_count)
                           ? k_cam_res[st.res_idx].name : "?";

    // PSRAM 剩余量：用 heap_caps 取真实可用值，而不是总容量
    const size_t psram_free = heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024;
    // 内部 RAM 剩余量 —— 这是 sendto 返回 ENOMEM 的真正来源。
    // WiFi 的静态 TX/RX 缓冲都只能放内部 DRAM（约 257KiB 可分配），
    // PSRAM 再多也帮不上忙。排查图传卡顿时必须先看这个值。
    const size_t iram_free = heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024;
    const size_t iram_min = heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL) / 1024;

    char body[512];
    snprintf(body, sizeof(body),
             "{\"res\":\"%s\",\"res_idx\":%d,\"fps\":%d,\"fps_max\":%d,"
             "\"q\":%d,\"qbase\":%d,\"adown\":%u,\"aup\":%u,"
             "\"rate_kbps\":%u,\"rate_target\":%d,"
             "\"frames_total\":%u,\"avg_kb\":%u,\"last_kb\":%u,"
             "\"queue\":%u,\"dropped\":%u,\"null_frames\":%u,"
             "\"streaming\":%d,\"psram_free_kb\":%u,"
             "\"iram_free_kb\":%u,\"iram_min_kb\":%u}",
             res_name, st.res_idx, st.fps, st.fps_ceiling,
             st.quality, st.quality_base,
             (unsigned)st.adapt_down_count, (unsigned)st.adapt_up_count,
             (unsigned)st.rate_kbps, RATE_TARGET_KBPS,
             (unsigned)st.frames_total, (unsigned)st.avg_kb, (unsigned)st.last_kb,
             (unsigned)st.queue_depth, (unsigned)st.dropped,
             (unsigned)st.null_frames,
             st.streaming ? 1 : 0, (unsigned)psram_free,
             (unsigned)iram_free, (unsigned)iram_min);

    char header[160];
    int hl = snprintf(header, sizeof(header),
                      "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                      "Cache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\n"
                      "Content-Length: %d\r\nConnection: close\r\n\r\n",
                      (int)strlen(body));
    send_all(sock, header, hl);
    send_all(sock, body, strlen(body));
}

// ==================== 拍照 ====================
static void handle_capture(int sock, const char *query)
{
    // 解析 ?res=N。默认 7 = QSXGA 2560x1920（真正的 5MP）。
    // 旧代码默认 5（UXGA 1600x1200，只有 2MP）却标着"5MP"，属于谎报。
    // 已实测 QSXGA 在本板可正常出帧（约 120~150KB）。
    int res_idx = 7;
    const char *p = strstr(query, "res=");
    if (p) {
        int v = atoi(p + 4);
        if (v >= 0 && v < k_cam_res_count) res_idx = v;
    }

    // 暂停UDP推流，换分辨率拍照，再恢复
    bool was_streaming = vision_udp_set_streaming(false);
    vTaskDelay(pdMS_TO_TICKS(150));
    // ★ 必须清队列：否则队列里的推流旧帧会被当成拍照结果返回
    vision_udp_drain_fb_queue();
    int saved_res = cam_get_stream_res();
    const int actual_res = cam_set_snapshot_res(res_idx);
    if (actual_res < 0) {
        cam_set_stream_res(saved_res);
        vision_udp_set_streaming(was_streaming);
        send_text_response(sock, "ERR bad res");
        return;
    }

    // 切分辨率后首帧可能为空，重试
    camera_fb_t *fb = NULL;
    for (int tries = 0; tries < 10 && !fb; tries++) {
        fb = cam_capture();
        if (!fb) vTaskDelay(pdMS_TO_TICKS(150));
    }
    if (!fb) {
        cam_set_stream_res(saved_res);
        vision_udp_set_streaming(was_streaming);
        send_text_response(sock, "ERR capture failed");
        return;
    }

    char header[160];
    int hl = snprintf(header, sizeof(header),
                      "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\n"
                      "Content-Length: %u\r\nConnection: close\r\n\r\n",
                      (unsigned)fb->len);
    ESP_LOGI(TAG, "HTTP拍照 %s %u字节", k_cam_res[actual_res].name, (unsigned)fb->len);
    send_all(sock, header, hl);
    send_all(sock, (const char *)fb->buf, fb->len);
    cam_release(fb);

    cam_set_stream_res(saved_res);
    vision_udp_set_streaming(was_streaming);
}

// ==================== MJPEG 流 ====================
// 网页预览：固定 VGA @5fps，超 30KB 的帧直接跳过。
//
// 为什么要限速：网页预览和 UDP 主图传共用同一个摄像头。早先这里按
// cam_get_fps()（20fps）无限制取帧，会和 UDP 采集任务抢帧缓冲，
// 而且 TCP+MJPEG 每帧都要等 ACK，高码率下延迟堆积严重。
// 实测未限速时 /stream 只有 0.25fps —— 越"努力"发越卡。
// 现在降级到 VGA@5fps，只作为"看个大概"的窗口，不参与性能评估。
#define PREVIEW_FPS        5
#define PREVIEW_INTERVAL_MS (1000 / PREVIEW_FPS)
#define PREVIEW_MAX_FRAME_BYTES (30 * 1024)

static void handle_stream(int sock)
{
    static const char k_hdr[] =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
        "Cache-Control: no-cache\r\nConnection: close\r\n\r\n";
    send_all(sock, k_hdr, sizeof(k_hdr) - 1);

    // 进入预览时降档到 VGA，退出时恢复。保存原值以便还原。
    const int saved_res = cam_get_stream_res();
    cam_set_preview_res(0);   // 0 = VGA 640x480

    while (1) {
        int64_t t0 = esp_timer_get_time();
        camera_fb_t *fb = cam_capture();
        if (!fb) { vTaskDelay(pdMS_TO_TICKS(100)); continue; }

        if (fb->format == PIXFORMAT_JPEG && fb->len <= PREVIEW_MAX_FRAME_BYTES) {
            char part[96];
            int pl = snprintf(part, sizeof(part),
                              "--frame\r\nContent-Type: image/jpeg\r\n"
                              "Content-Length: %u\r\n\r\n", (unsigned)fb->len);
            if (send_all(sock, part, pl) < 0 ||
                send_all(sock, (const char *)fb->buf, fb->len) < 0 ||
                send_all(sock, "\r\n", 2) < 0) {
                cam_release(fb);
                break;   // 浏览器断开
            }
        }
        // 超过上限的帧不发送但仍要归还，否则帧池耗尽
        cam_release(fb);

        int elapsed_ms = (int)((esp_timer_get_time() - t0) / 1000);
        int remain = PREVIEW_INTERVAL_MS - elapsed_ms;
        if (remain > 0) vTaskDelay(pdMS_TO_TICKS(remain));
    }

    cam_set_preview_res(saved_res);   // 恢复推流分辨率
}

// ==================== 连接处理 ====================
static void http_conn_task(void *pv)
{
    int sock = (int)(intptr_t)pv;
    char buf[BUF_SIZE + 1];
    int len = recv(sock, buf, BUF_SIZE, 0);
    if (len <= 0) { close(sock); s_stream_clients--; vTaskDelete(NULL); return; }
    buf[len] = '\0';

    // 解析请求行 GET /path?query HTTP/1.1
    char *line_end = strstr(buf, "\r\n");
    if (line_end) *line_end = '\0';

    if (strncmp(buf, "GET /stream", 11) == 0) {
        ESP_LOGI(TAG, "浏览器打开图传流");
        handle_stream(sock);
        ESP_LOGI(TAG, "浏览器断开图传流");
    } else if (strncmp(buf, "GET /status", 11) == 0) {
        handle_status(sock);
    } else if (strncmp(buf, "GET /capture", 12) == 0) {
        char *q = strchr(buf, '?');
        handle_capture(sock, q ? q : "");
    } else if (strncmp(buf, "GET /", 5) == 0 || strncmp(buf, "GET /index", 10) == 0) {
        char header[128];
        int hl = snprintf(header, sizeof(header),
                          "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                          "Content-Length: %d\r\nConnection: close\r\n\r\n",
                          (int)sizeof(k_index_html) - 1);
        send_all(sock, header, hl);
        send_all(sock, k_index_html, sizeof(k_index_html) - 1);
    } else {
        send_text_response(sock, "404 not found");
    }

    // 让对端收完数据再关闭（HTTP close语义）
    struct linger lg = { .l_onoff = 1, .l_linger = 2 };
    setsockopt(sock, SOL_SOCKET, SO_LINGER, &lg, sizeof(lg));
    close(sock);
    if (strncmp(buf, "GET /stream", 11) == 0) s_stream_clients--;
    vTaskDelete(NULL);
}

// ==================== 监听任务 ====================
static void http_server_task(void *pv)
{
    int srv = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (srv < 0) {
        ESP_LOGE(TAG, "socket 创建失败 errno=%d", errno);
        vTaskDelete(NULL);
        return;
    }
    int reuse = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in addr = { 0 };
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(HTTP_PORT);
    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
        listen(srv, 4) < 0) {
        ESP_LOGE(TAG, "bind/listen %d 失败 errno=%d", HTTP_PORT, errno);
        close(srv);
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(TAG, "浏览器图传服务就绪: http://192.168.5.1 (端口 %d)", HTTP_PORT);

    while (1) {
        struct sockaddr_in client;
        socklen_t clen = sizeof(client);
        int conn = accept(srv, (struct sockaddr *)&client, &clen);
        if (conn < 0) { vTaskDelay(pdMS_TO_TICKS(50)); continue; }

        // 请求行里判断是否 /stream，提前限流
        char peek[64] = { 0 };
        int n = recv(conn, peek, sizeof(peek) - 1, MSG_PEEK);
        bool is_stream = (n > 0 && strncmp(peek, "GET /stream", 11) == 0);
        if (is_stream && s_stream_clients >= STREAM_CLIENTS_MAX) {
            send_text_response(conn, "ERR stream busy");
            close(conn);
            continue;
        }
        if (is_stream) s_stream_clients++;

        // 6KB栈：MJPEG分段发送无需大缓冲
        // 绑 core 1：MJPEG 发送同样不能让开 WiFi 协议栈所在的 core 0
        if (xTaskCreatePinnedToCore(http_conn_task, "hconn", 6144,
                                    (void *)(intptr_t)conn, 5, NULL, 1) != pdPASS) {
            close(conn);
            if (is_stream) s_stream_clients--;
        }
    }
}

esp_err_t vision_http_start(void)
{
    if (xTaskCreate(http_server_task, "vhttp", 6144, NULL, 4, NULL) != pdPASS) {
        return ESP_FAIL;
    }
    return ESP_OK;
}
