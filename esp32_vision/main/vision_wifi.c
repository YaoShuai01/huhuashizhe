/**
 * vision_wifi - WiFi STA 接入飞控热点
 */
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_mac.h"

static const char *TAG = "VWIFI";

// 与飞控 esp32_drone/main/main.c 的 AP 配置保持一致
#define WIFI_SSID    "HuHuaShiZhe-Drone"
#define WIFI_PASS    ""

#define WIFI_CONNECTED_BIT BIT0

static EventGroupHandle_t s_event;
static char s_ip[16] = "0.0.0.0";

static void ip_event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *ev = (ip_event_got_ip_t *)data;
        snprintf(s_ip, sizeof(s_ip), IPSTR, IP2STR(&ev->ip_info.ip));
        ESP_LOGI(TAG, "已获得IP: %s", s_ip);
        xEventGroupSetBits(s_event, WIFI_CONNECTED_BIT);
    }
}

static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        ESP_LOGW(TAG, "与飞控AP断开，2秒后重试...");
        vTaskDelay(pdMS_TO_TICKS(2000));
        esp_wifi_connect();
    }
}

esp_err_t vision_wifi_start(void)
{
    s_event = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &ip_event_handler, NULL));

    wifi_config_t wc = { 0 };
    strlcpy((char *)wc.sta.ssid, WIFI_SSID, sizeof(wc.sta.ssid));
    strlcpy((char *)wc.sta.password, WIFI_PASS, sizeof(wc.sta.password));
    wc.sta.scan_method = WIFI_FAST_SCAN;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wc));
    ESP_ERROR_CHECK(esp_wifi_start());

    ESP_LOGI(TAG, "STA 启动，正在接入飞控热点 \"%s\"...", WIFI_SSID);
    return ESP_OK;
}

bool vision_wifi_wait_ip(int timeout_s)
{
    EventBits_t bits = xEventGroupWaitBits(s_event, WIFI_CONNECTED_BIT,
                                           pdFALSE, pdFALSE,
                                           pdMS_TO_TICKS(timeout_s * 1000));
    return (bits & WIFI_CONNECTED_BIT) != 0;
}

const char *vision_wifi_ip_str(void)
{
    return s_ip;
}
