/**
 * 护花使者 - 机载视觉板 (ESP32-S3-N16R8 CAM + OV5640 5MP)
 *
 * 职责：采集 JPEG → UDP 8889 推流/拍照接口（协议见 vision_udp.h）
 * 网络：STA 接入飞控热点 HuHuaShiZhe-Drone，与手机同网段
 * 独立固件，与飞控工程 esp32_drone 互不影响
 *
 * 启动流程：NVS → WiFi STA → 摄像头(OV5640) → UDP服务 → 心跳日志
 */
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_log.h"
#include "esp_psram.h"
#include "nvs_flash.h"

#include "vision_wifi.h"
#include "vision_cam.h"
#include "vision_udp.h"
#include "vision_http.h"
#include "vision_serial.h"

static const char *TAG = "VISION";

static void heartbeat_task(void *pv)
{
    while (1) {
        ESP_LOGI(TAG, "运行中 ip=%s sensor=%s streaming=%d",
                 vision_wifi_ip_str(), cam_sensor_name(),
                 (int)vision_udp_streaming());
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}

void app_main(void)
{
    ESP_LOGI(TAG, "=== 护花使者视觉板启动 ===");

    // NVS（WiFi需要）
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    ESP_LOGI(TAG, "PSRAM: %d KB", (int)(esp_psram_get_size() / 1024));

    // WiFi（不阻塞主流程，后台自动重连）
    vision_wifi_start();

    // 摄像头
    err = vision_cam_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "摄像头初始化失败，系统继续运行（网络仍可用，便于排查）");
    }

    // UDP 图传服务
    vision_udp_start();

    // 串口图传（USB线直连电脑看画面）
    vision_serial_start();

    // 浏览器图传窗口（MJPEG）
    vision_http_start();

    // 等IP（最长25秒），拿到后打一条汇总
    if (vision_wifi_wait_ip(25)) {
        ESP_LOGI(TAG, "就绪！手机发送 VINFO 到 %s:%d 查询状态",
                 vision_wifi_ip_str(), VISION_UDP_PORT);
    } else {
        ESP_LOGW(TAG, "25秒未接入飞控热点，浏览器图传仍可用: http://192.168.5.1");
    }

    xTaskCreate(heartbeat_task, "vheart", 4096, NULL, 3, NULL);
}
