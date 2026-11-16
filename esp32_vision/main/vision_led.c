/**
 * vision_led - 板载 WS2812 全彩灯（GPIO48）
 *
 * 节奏（2 秒周期）：白闪 60ms → 间隔 50ms → 红闪 60ms → 熄灭到 2 秒
 */
#include "vision_led.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/rmt_tx.h"
#include "driver/rmt_encoder.h"
#include "driver/gpio.h"
#include "esp_check.h"
#include "esp_log.h"

static const char *TAG = "VLED";

#define LED_GPIO          48
#define LED_RESOLUTION_HZ 10000000  // 10MHz，1 tick = 0.1us
#define LED_CYCLE_MS      2000
#define LED_PULSE_MS      60
#define LED_GAP_MS        50

#define LED2_GPIO             2
#define LED2_HALF_PERIOD_MS   62   // 半周期 62ms，约 8Hz（1 秒 8 次）

static rmt_channel_handle_t s_chan = NULL;
static rmt_encoder_handle_t s_encoder = NULL;

static void led_write(uint8_t r, uint8_t g, uint8_t b)
{
    // WS2812 数据顺序为 GRB
    uint8_t grb[3] = {g, r, b};
    rmt_transmit_config_t tx_cfg = {.loop_count = 0};
    rmt_transmit(s_chan, s_encoder, grb, sizeof(grb), &tx_cfg);
    rmt_tx_wait_all_done(s_chan, 100);
}

static void led_task(void *arg)
{
    while (1) {
        TickType_t start = xTaskGetTickCount();

        led_write(160, 160, 160);            // 白
        vTaskDelay(pdMS_TO_TICKS(LED_PULSE_MS));
        led_write(0, 0, 0);
        vTaskDelay(pdMS_TO_TICKS(LED_GAP_MS));
        led_write(200, 0, 0);                // 红
        vTaskDelay(pdMS_TO_TICKS(LED_PULSE_MS));
        led_write(0, 0, 0);

        uint32_t elapsed = (xTaskGetTickCount() - start) * portTICK_PERIOD_MS;
        if (elapsed < LED_CYCLE_MS) {
            vTaskDelay(pdMS_TO_TICKS(LED_CYCLE_MS - elapsed));
        }
    }
}

// GPIO2 板载用户灯：1 秒 8 次频闪
static void led2_task(void *arg)
{
    bool on = false;
    while (1) {
        on = !on;
        gpio_set_level(LED2_GPIO, on ? 1 : 0);
        vTaskDelay(pdMS_TO_TICKS(LED2_HALF_PERIOD_MS));
    }
}

esp_err_t vision_led_start(void)
{
    rmt_tx_channel_config_t tx_chan_cfg = {
        .clk_src = RMT_CLK_SRC_DEFAULT,
        .gpio_num = LED_GPIO,
        .mem_block_symbols = 48,
        .resolution_hz = LED_RESOLUTION_HZ,
        .trans_queue_depth = 4,
    };
    ESP_RETURN_ON_ERROR(rmt_new_tx_channel(&tx_chan_cfg, &s_chan), TAG, "rmt channel");

    rmt_bytes_encoder_config_t enc_cfg = {
        .bit0 = {.level0 = 1, .duration0 = 3, .level1 = 0, .duration1 = 9},
        .bit1 = {.level0 = 1, .duration0 = 9, .level1 = 0, .duration1 = 3},
        .flags.msb_first = 1,
    };
    ESP_RETURN_ON_ERROR(rmt_new_bytes_encoder(&enc_cfg, &s_encoder), TAG, "encoder");
    ESP_RETURN_ON_ERROR(rmt_enable(s_chan), TAG, "enable");

    gpio_config_t io_cfg = {
        .pin_bit_mask = 1ULL << LED2_GPIO,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_RETURN_ON_ERROR(gpio_config(&io_cfg), TAG, "gpio2");
    gpio_set_level(LED2_GPIO, 0);

    if (xTaskCreate(led_task, "vled", 4096, NULL, 2, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    if (xTaskCreate(led2_task, "vled2", 3072, NULL, 2, NULL) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    ESP_LOGI(TAG, "WS2812(GPIO%d) + 用户灯(GPIO%d) 已启动", LED_GPIO, LED2_GPIO);
    return ESP_OK;
}
