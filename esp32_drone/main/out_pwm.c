/**
 * out_pwm.c - LEDC PWM 输出
 * 护花使者 ESP32-S3 飞控
 */
#include "driver/ledc.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "out_pwm.h"
#include "prm_params.h"

static const char *TAG = "OUT";

// ==================== 引脚定义 ====================
#define PIN_FRONT_RIGHT   GPIO_NUM_1
#define PIN_FRONT_LEFT    GPIO_NUM_4
#define PIN_BACK_RIGHT    GPIO_NUM_21
#define PIN_BACK_LEFT     GPIO_NUM_12
#define PIN_SPRAY         GPIO_NUM_18

// LEDC 通道
#define LEDC_CH_FR  LEDC_CHANNEL_0
#define LEDC_CH_FL  LEDC_CHANNEL_1
#define LEDC_CH_BR  LEDC_CHANNEL_2
#define LEDC_CH_BL  LEDC_CHANNEL_3
#define LEDC_CH_SP  LEDC_CHANNEL_4

// 电调 PWM：50Hz/14bit，脉宽 1ms=819, 2ms=1638
#define ESC_FREQ_HZ      50
#define ESC_DUTY_RES     14
#define ESC_PULSE_MIN    819    // 1.0ms 最低油门(停转)
#define ESC_PULSE_MAX    1638   // 2.0ms 最大油门
#define ESC_FULL_DUTY    ((1 << ESC_DUTY_RES) - 1)   // 16383

// 水泵 PWM：5kHz/8bit（MOS 管调速）
#define PUMP_FREQ_HZ     5000
#define PUMP_DUTY_RES    8

static const char *MOTOR_NAMES[4] = {"FR(GPIO1)", "FL(GPIO4)", "BR(GPIO21)", "BL(GPIO12)"};

static void esc_set_channel(int ch, uint32_t duty)
{
    ledc_set_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)ch, duty);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)ch);
}

// ==================== 电调信号自检 ====================
// 只输出 1ms 最低油门(停转)，确认信号链路正常；电调会响"哔-哔"提示音
static void esc_self_test(void)
{
    ESP_LOGI(TAG, "========== 电调信号自检开始 ==========");
    for (int i = 0; i < 4; i++) {
        ESP_LOGI(TAG, "自检: %s 输出最低油门 1.0ms (停转)", MOTOR_NAMES[i]);
        esc_set_channel(LEDC_CH_FR + i, ESC_PULSE_MIN);
        vTaskDelay(pdMS_TO_TICKS(200));
    }
    ESP_LOGI(TAG, "自检: 4通道最低油门写入完成 [MARK-A]");
    for (int i = 0; i < 4; i++) {
        uint32_t duty = ledc_get_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)(LEDC_CH_FR + i));
        int tenths = (int)(duty * 20 / 1638);   // 换算为 0.1ms 单位
        ESP_LOGI(TAG, "自检: %s duty=%lu (%d.%dms)", MOTOR_NAMES[i],
                 (unsigned long)duty, tenths / 10, tenths % 10);
    }
    ESP_LOGI(TAG, "自检回读完成 [MARK-B]");
    ESP_LOGI(TAG, "========== 电调信号自检完成 ==========");
    ESP_LOGI(TAG, "警告: 请确认未安装螺旋桨! 解锁后电机将转动");
}

esp_err_t out_init(void)
{
    // GPIO 配置
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << PIN_FRONT_RIGHT) | (1ULL << PIN_FRONT_LEFT) |
                        (1ULL << PIN_BACK_RIGHT)  | (1ULL << PIN_BACK_LEFT) |
                        (1ULL << PIN_SPRAY),
        .mode         = GPIO_MODE_OUTPUT,
        .pull_up_en   = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    gpio_config(&io_conf);
    gpio_set_level(PIN_FRONT_RIGHT, 0);
    gpio_set_level(PIN_FRONT_LEFT, 0);
    gpio_set_level(PIN_BACK_RIGHT, 0);
    gpio_set_level(PIN_BACK_LEFT, 0);
    gpio_set_level(PIN_SPRAY, 0);
    ESP_LOGI(TAG, "GPIO initialized: FR=1, FL=4, BR=21, BL=12, SP=18");

    // 电调定时器: 50Hz, 14bit
    ledc_timer_config_t esc_timer = {
        .speed_mode       = LEDC_LOW_SPEED_MODE,
        .duty_resolution  = ESC_DUTY_RES,
        .timer_num        = LEDC_TIMER_0,
        .freq_hz          = ESC_FREQ_HZ,
        .clk_cfg          = LEDC_AUTO_CLK
    };
    ESP_ERROR_CHECK(ledc_timer_config(&esc_timer));

    // 水泵定时器: 5kHz, 8bit（独立）
    ledc_timer_config_t pump_timer = {
        .speed_mode       = LEDC_LOW_SPEED_MODE,
        .duty_resolution  = PUMP_DUTY_RES,
        .timer_num        = LEDC_TIMER_1,
        .freq_hz          = PUMP_FREQ_HZ,
        .clk_cfg          = LEDC_AUTO_CLK
    };
    ESP_ERROR_CHECK(ledc_timer_config(&pump_timer));

    ledc_channel_config_t channels[] = {
        {.gpio_num = PIN_FRONT_RIGHT, .speed_mode = LEDC_LOW_SPEED_MODE,
         .channel = LEDC_CH_FR, .timer_sel = LEDC_TIMER_0,
         .duty = 0, .hpoint = 0, .intr_type = LEDC_INTR_DISABLE,
         .flags = {.output_invert = 0}},
        {.gpio_num = PIN_FRONT_LEFT, .speed_mode = LEDC_LOW_SPEED_MODE,
         .channel = LEDC_CH_FL, .timer_sel = LEDC_TIMER_0,
         .duty = 0, .hpoint = 0, .intr_type = LEDC_INTR_DISABLE,
         .flags = {.output_invert = 0}},
        {.gpio_num = PIN_BACK_RIGHT, .speed_mode = LEDC_LOW_SPEED_MODE,
         .channel = LEDC_CH_BR, .timer_sel = LEDC_TIMER_0,
         .duty = 0, .hpoint = 0, .intr_type = LEDC_INTR_DISABLE,
         .flags = {.output_invert = 0}},
        {.gpio_num = PIN_BACK_LEFT, .speed_mode = LEDC_LOW_SPEED_MODE,
         .channel = LEDC_CH_BL, .timer_sel = LEDC_TIMER_0,
         .duty = 0, .hpoint = 0, .intr_type = LEDC_INTR_DISABLE,
         .flags = {.output_invert = 0}},
        {.gpio_num = PIN_SPRAY, .speed_mode = LEDC_LOW_SPEED_MODE,
         .channel = LEDC_CH_SP, .timer_sel = LEDC_TIMER_1,
         .duty = 0, .hpoint = 0, .intr_type = LEDC_INTR_DISABLE,
         .flags = {.output_invert = 0}},
    };
    for (int i = 0; i < 5; i++) {
        ESP_ERROR_CHECK(ledc_channel_config(&channels[i]));
    }
    ledc_fade_func_install(0);

    // 上电立即输出最低油门(1ms)到所有电调通道
    // 重要: 电调上电时必须收到 1ms 低油门信号，否则进入校准/编程模式
    for (int i = 0; i < 4; i++) {
        esc_set_channel(LEDC_CH_FR + i, ESC_PULSE_MIN);
    }
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_SP, 0);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_SP);

    ESP_LOGI(TAG, "PWM initialized: ESC=50Hz/14bit(1-2ms), Pump=5kHz/8bit");

    esc_self_test();

    return ESP_OK;
}

void out_set_motors(const float motor[4])
{
    // 归一化 0..1 → 脉宽 1..2ms（1638-819=819）
    for (int i = 0; i < 4; i++) {
        float m = motor[i];
        if (m < 0.0f) m = 0.0f;
        if (m > 1.0f) m = 1.0f;
        uint32_t duty = (uint32_t)(ESC_PULSE_MIN + m * (ESC_PULSE_MAX - ESC_PULSE_MIN));
        esc_set_channel(LEDC_CH_FR + i, duty);
    }
}

void out_set_spray(int level)
{
    const prm_param_t *p = prm_get();
    if (level < 0) level = 0;
    if (level > 6) level = 6;
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_SP, p->pump_duty[level]);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_SP);
}

void out_emergency(void)
{
    float zero[4] = {0.0f, 0.0f, 0.0f, 0.0f};
    out_set_motors(zero);   // 全部回 1ms 停转
    out_set_spray(0);       // 水泵关闭
    ESP_LOGW(TAG, "紧急输出: 电机全 1ms，水泵关闭");
}
