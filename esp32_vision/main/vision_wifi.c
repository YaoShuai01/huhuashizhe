/**
 * vision_wifi - WiFi AP+STA 双模式
 *
 * STA：接入飞控热点 HuHuaShiZhe-Drone（生产链路）
 * AP ：自开热点 HuHuaShiZhe-CAM（192.168.5.1），电脑/手机直连浏览器看图传，
 *      飞控不开机也能玩。两网并存，服务监听 0.0.0.0 双网可达。
 */
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_mac.h"
#include "lwip/inet.h"

static const char *TAG = "VWIFI";

// 与飞控 esp32_drone/main/main.c 的 AP 配置保持一致
#define WIFI_SSID    "HuHuaShiZhe-Drone"
#define WIFI_PASS    ""

// 视觉板自开热点（调试/体验用）。子网用 5.x 避开飞控的 4.x
#define CAM_AP_SSID  "HuHuaShiZhe-CAM"
#define CAM_AP_IP    "192.168.5.1"
#define CAM_AP_MASK  "255.255.255.0"

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

    // AP 网段固定为 192.168.5.x（避开飞控 4.x），拿到 netif 句柄后改IP
    esp_netif_t *ap_netif = esp_netif_create_default_wifi_ap();
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &ip_event_handler, NULL));

    // AP 配置
    wifi_config_t ap_cfg = { 0 };
    strlcpy((char *)ap_cfg.ap.ssid, CAM_AP_SSID, sizeof(ap_cfg.ap.ssid));
    ap_cfg.ap.ssid_len = strlen(CAM_AP_SSID);
    ap_cfg.ap.channel = 1;
    ap_cfg.ap.max_connection = 3;
    ap_cfg.ap.authmode = WIFI_AUTH_OPEN;

    // STA 配置
    wifi_config_t sta_cfg = { 0 };
    strlcpy((char *)sta_cfg.sta.ssid, WIFI_SSID, sizeof(sta_cfg.sta.ssid));
    strlcpy((char *)sta_cfg.sta.password, WIFI_PASS, sizeof(sta_cfg.sta.password));
    sta_cfg.sta.scan_method = WIFI_FAST_SCAN;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap_cfg));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &sta_cfg));
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));   // 关省电：修复与飞控softAP周期掉线
    ESP_ERROR_CHECK(esp_wifi_start());

    // 改 AP 网段为 192.168.5.x
    esp_netif_dhcps_stop(ap_netif);
    esp_netif_ip_info_t ip = { 0 };
    ip.ip.addr = ipaddr_addr(CAM_AP_IP);
    ip.netmask.addr = ipaddr_addr(CAM_AP_MASK);
    ip.gw.addr = ipaddr_addr(CAM_AP_IP);
    esp_netif_set_ip_info(ap_netif, &ip);
    esp_netif_dhcps_start(ap_netif);

    ESP_LOGI(TAG, "AP+STA 已启动：热点 \"%s\"(浏览器 http://%s) / STA 接入 \"%s\"",
             CAM_AP_SSID, CAM_AP_IP, WIFI_SSID);
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
