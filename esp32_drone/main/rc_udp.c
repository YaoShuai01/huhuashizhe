/**
 * rc_udp.c - UDP 遥控输入
 * 护花使者 ESP32-S3 飞控
 * 协议解析沿用 v3：ARM/PIT/ROL/THR/YAW/SPR/TAKEOFF/LAND，K:V; 分隔
 */
#include <string.h>
#include <stdlib.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "rc_udp.h"
#include "prm_params.h"

static const char *TAG = "RC";

#define UDP_PORT       8888
#define UDP_BUF_SIZE   256

// 遥控输入邮箱（udp 任务写，commander 读）
static rc_input_t s_rc;
static SemaphoreHandle_t s_rc_mutex = NULL;

// 上升沿检测（TAKEOFF/LAND 一次性指令）
static bool s_prev_takeoff = false;
static bool s_prev_land = false;

void rc_init(void)
{
    s_rc_mutex = xSemaphoreCreateMutex();
    memset(&s_rc, 0, sizeof(s_rc));
    ESP_LOGI(TAG, "遥控输入初始化 (UDP 端口 %d)", UDP_PORT);
}

void rc_get_input(rc_input_t *out)
{
    if (s_rc_mutex == NULL) return;
    xSemaphoreTake(s_rc_mutex, portMAX_DELAY);
    memcpy(out, &s_rc, sizeof(s_rc));
    xSemaphoreGive(s_rc_mutex);
}

// ==================== 指令解析（沿用 v3 语义） ====================
static void rc_parse(const char *buf, int len)
{
    char cmd[UDP_BUF_SIZE];
    strncpy(cmd, buf, len < UDP_BUF_SIZE ? len : UDP_BUF_SIZE - 1);
    cmd[len < UDP_BUF_SIZE ? len : UDP_BUF_SIZE - 1] = '\0';

    // 本地先解析，完成后一次性发布（减小临界区）
    rc_input_t local;
    xSemaphoreTake(s_rc_mutex, portMAX_DELAY);
    memcpy(&local, &s_rc, sizeof(s_rc));
    xSemaphoreGive(s_rc_mutex);

    char *saveptr1;
    char *token = strtok_r(cmd, ";", &saveptr1);
    while (token != NULL) {
        while (*token == ' ' || *token == '\r' || *token == '\n') token++;
        if (*token == '\0') { token = strtok_r(NULL, ";", &saveptr1); continue; }

        char *colon = strchr(token, ':');
        if (colon == NULL) { token = strtok_r(NULL, ";", &saveptr1); continue; }

        *colon = '\0';
        char *key = token;
        char *val = colon + 1;

        char *kend = key + strlen(key) - 1;
        while (kend >= key && (*kend == ' ' || *kend == '\r' || *kend == '\n')) { *kend = '\0'; kend--; }

        int v = atoi(val);

        if (strcmp(key, "ARM") == 0) {
            local.arm = (v != 0);
        } else if (strcmp(key, "PIT") == 0) {
            local.pitch = (v < -100) ? -100 : ((v > 100) ? 100 : v);
        } else if (strcmp(key, "ROL") == 0) {
            local.roll = (v < -100) ? -100 : ((v > 100) ? 100 : v);
        } else if (strcmp(key, "THR") == 0) {
            local.throttle = (v < -100) ? -100 : ((v > 100) ? 100 : v);
        } else if (strcmp(key, "YAW") == 0) {
            local.yaw = (v < -100) ? -100 : ((v > 100) ? 100 : v);
        } else if (strcmp(key, "SPR") == 0) {
            local.spray = (v < 0) ? 0 : ((v > 6) ? 6 : v);
        } else if (strcmp(key, "TAKEOFF") == 0) {
            bool now = (v != 0);
            if (now && !s_prev_takeoff) local.takeoff_pending = true;   // 上升沿
            s_prev_takeoff = now;
        } else if (strcmp(key, "LAND") == 0) {
            bool now = (v != 0);
            if (now && !s_prev_land) local.land_pending = true;          // 上升沿
            s_prev_land = now;
        }

        token = strtok_r(NULL, ";", &saveptr1);
    }

    local.last_rx_ms = (uint32_t)(esp_timer_get_time() / 1000);

    xSemaphoreTake(s_rc_mutex, portMAX_DELAY);
    memcpy(&s_rc, &local, sizeof(s_rc));
    xSemaphoreGive(s_rc_mutex);
}

// ==================== UDP 服务器任务 ====================
static void udp_server_task(void *pvParameters)
{
    char rx_buf[UDP_BUF_SIZE];
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_addr_len = sizeof(client_addr);

    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock < 0) {
        ESP_LOGE(TAG, "UDP socket 创建失败: errno %d", errno);
        vTaskDelete(NULL);
        return;
    }

    struct timeval timeout = { .tv_sec = 0, .tv_usec = 500000 };
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    server_addr.sin_port = htons(UDP_PORT);

    if (bind(sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        ESP_LOGE(TAG, "UDP bind 失败: errno %d", errno);
        close(sock);
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(TAG, "UDP 服务器启动，监听端口 %d", UDP_PORT);

    while (1) {
        int len = recvfrom(sock, rx_buf, UDP_BUF_SIZE - 1, 0,
                           (struct sockaddr *)&client_addr, &client_addr_len);
        if (len < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
            ESP_LOGE(TAG, "UDP recvfrom 错误: errno %d", errno);
            continue;
        }
        if (len > 0) {
            rx_buf[len] = '\0';
            rc_parse(rx_buf, len);
        }
    }

    close(sock);
    vTaskDelete(NULL);
}

void rc_udp_task_start(void)
{
    xTaskCreatePinnedToCore(udp_server_task, "udp_server", 4096, NULL, 5, NULL, 0);
    ESP_LOGI(TAG, "UDP 任务已创建 (core0, prio5)");
}
