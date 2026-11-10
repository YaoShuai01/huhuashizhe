/**
 * vision_http - MJPEG 浏览器图传实现
 */
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
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
"img{width:100%;max-width:720px;border-radius:8px}"
"a.btn{display:inline-block;margin:8px 6px;padding:10px 18px;background:#5b6cff;color:#fff;"
"border-radius:8px;text-decoration:none;font-size:15px}"
"p{color:#999;font-size:13px;margin:6px 0}"
"</style></head><body>"
"<h3>护花使者 · 实时图传</h3>"
"<img src='/stream' alt='等待画面...'>"
"<div>"
"<a class='btn' href='/capture'>拍 5MP 照片</a>"
"<a class='btn' href='/capture?res=5'>拍 UXGA 照片</a>"
"</div>"
"<p>分辨率/帧率默认 XGA 1024x768 @12fps，由固件 cam_set_stream_params 控制</p>"
"<p>本页为体验窗口；正式图传在 护花使者APP 无人机页</p>"
"</body></html>";

// ==================== 拍照 ====================
static void handle_capture(int sock, const char *query)
{
    // 解析 ?res=N（默认 UXGA——OV5640@20MHz 的稳定拍照档）
    int res_idx = 5;
    const char *p = strstr(query, "res=");
    if (p) {
        int v = atoi(p + 4);
        if (v >= 0 && v < k_cam_res_count) res_idx = v;
    }

    // 暂停UDP推流，换分辨率拍照，再恢复
    bool was_streaming = vision_udp_set_streaming(false);
    vTaskDelay(pdMS_TO_TICKS(150));
    int saved_res = cam_get_stream_res();
    cam_set_stream_res(res_idx);

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
    ESP_LOGI(TAG, "HTTP拍照 %s %u字节", k_cam_res[res_idx].name, (unsigned)fb->len);
    send_all(sock, header, hl);
    send_all(sock, (const char *)fb->buf, fb->len);
    cam_release(fb);

    cam_set_stream_res(saved_res);
    vision_udp_set_streaming(was_streaming);
}

// ==================== MJPEG 流 ====================
static void handle_stream(int sock)
{
    static const char k_hdr[] =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n"
        "Cache-Control: no-cache\r\nConnection: close\r\n\r\n";
    send_all(sock, k_hdr, sizeof(k_hdr) - 1);

    while (1) {
        int64_t t0 = esp_timer_get_time();
        camera_fb_t *fb = cam_capture();
        if (!fb) { vTaskDelay(pdMS_TO_TICKS(100)); continue; }

        if (fb->format == PIXFORMAT_JPEG) {
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
        cam_release(fb);

        int interval_ms = 1000 / cam_get_fps();
        int elapsed_ms = (int)((esp_timer_get_time() - t0) / 1000);
        int remain = interval_ms - elapsed_ms;
        if (remain > 0) vTaskDelay(pdMS_TO_TICKS(remain));
    }
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
        if (xTaskCreate(http_conn_task, "hconn", 6144,
                        (void *)(intptr_t)conn, 5, NULL) != pdPASS) {
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
