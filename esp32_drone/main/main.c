/**
 * 护花使者 - 无人机验证平台 (ESP32-S3) v2
 * 功能：WiFi AP + UDP 遥控 + 飞行状态机 + 高度模拟 + 矢量混控
 * 引脚定义：
 *   GPIO1  = 前右电机 (Front-Right)
 *   GPIO4  = 前左电机 (Front-Left)
 *   GPIO21 = 后右电机 (Back-Right)
 *   GPIO12 = 后左电机 (Back-Left)
 *   GPIO18 = 喷洒装置 (Spray)
 *
 * 通信协议 (UDP 端口 8888)：
 *   ARM:0/1    - 解锁/上锁
 *   PIT:-100~100 - 俯仰（前后移动）
 *   ROL:-100~100 - 横滚（左右移动）
 *   THR:-100~100 - 油门（上下升降，sticky）
 *   YAW:-100~100 - 偏航（左右旋转）
 *   SPR:0/1    - 喷洒开关
 *   TAKEOFF:1  - 一键起飞
 *   LAND:1     - 一键降落
 *
 * 飞行状态机：
 *   IDLE → ARMED → TAKING_OFF(0→35亮度,2s) → HOVERING(0.5m)
 *   HOVERING ↔ FLYING(油门控制高度)
 *   FLYING/HOVERING → LANDING(降至0.5m) → LANDING_FINAL(降至地面)
 *   LANDING_FINAL(低于0.5m松手) → 自动爬升回HOVERING
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "lwip/netdb.h"
#include "driver/ledc.h"
#include "driver/gpio.h"
#include "esp_timer.h"
#include "esp_mac.h"

static const char *TAG = "DRONE";

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

// ==================== WiFi AP 配置 ====================
#define WIFI_SSID      "HuHuaShiZhe-Drone"
#define WIFI_PASSWORD  ""
#define WIFI_CHANNEL   1
#define WIFI_MAX_CONN  1

// ==================== UDP 配置 ====================
#define UDP_PORT       8888
#define UDP_BUF_SIZE   256

// ==================== 飞行参数 ====================
#define HOVER_PWM       35     // 悬停(0.5m) PWM值 (35/255 ≈ 13.7%)
#define MAX_PWM         255    // 最大PWM
#define MIN_PWM         0      // 最小PWM
#define TAKEOFF_TIME_MS 2000   // 起飞持续时间(0→0.5m)
#define HOVER_ALTITUDE  50     // 悬停高度(0.5m) 内部单位
#define MAX_ALTITUDE    200    // 最大高度(2m) 内部单位
#define ALT_RATE_SCALE  2      // 高度变化速率

// ==================== 飞行状态枚举 ====================
typedef enum {
    STATE_IDLE = 0,       // 未解锁
    STATE_ARMED,          // 已解锁，等待起飞
    STATE_TAKING_OFF,     // 起飞中 (0→0.5m)
    STATE_HOVERING,       // 悬停在0.5m
    STATE_FLYING,         // 飞行中 (>0.5m)
    STATE_LANDING,        // 降落中 (→0.5m)
    STATE_LANDING_FINAL,  // 最终降落 (→地面)
    STATE_EMERGENCY       // 紧急停机
} flight_state_t;

// ==================== 全局状态 ====================
static flight_state_t g_state = STATE_IDLE;
static bool g_armed = false;
static int  g_pitch = 0;      // -100 ~ 100 (俯仰)
static int  g_roll = 0;       // -100 ~ 100 (横滚)
static int  g_throttle = 0;   // -100 ~ 100 (油门, sticky)
static int  g_yaw = 0;        // -100 ~ 100 (偏航)
static bool g_spray = false;

// 高度模拟
static int   g_altitude = 0;          // 当前高度 (0=地面, 50=0.5m悬停, 200=2m)
static int   g_target_altitude = 0;   // 目标高度
static int64_t g_takeoff_start = 0;   // 起飞开始时间
static int64_t g_landing_start = 0;   // 降落开始时间
static bool  g_onekey_takeoff = false; // 一键起飞标志
static bool  g_onekey_landing = false; // 一键降落标志

// 油门定住检测（用于手动起飞）
static int64_t g_throttle_hold_start = 0;
static bool    g_throttle_held = false;

// 心跳超时
static int64_t g_last_cmd_time = 0;
#define CMD_TIMEOUT_MS  3000

// ==================== LEDC PWM 初始化 ====================
static void ledc_init(void)
{
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

    ledc_timer_config_t ledc_timer = {
        .speed_mode       = LEDC_LOW_SPEED_MODE,
        .duty_resolution  = LEDC_TIMER_8_BIT,
        .timer_num        = LEDC_TIMER_0,
        .freq_hz          = 5000,
        .clk_cfg          = LEDC_AUTO_CLK
    };
    ESP_ERROR_CHECK(ledc_timer_config(&ledc_timer));

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
         .channel = LEDC_CH_SP, .timer_sel = LEDC_TIMER_0,
         .duty = 0, .hpoint = 0, .intr_type = LEDC_INTR_DISABLE,
         .flags = {.output_invert = 0}},
    };
    for (int i = 0; i < 5; i++) {
        ESP_ERROR_CHECK(ledc_channel_config(&channels[i]));
    }
    ledc_fade_func_install(0);
    ESP_LOGI(TAG, "LEDC PWM initialized (5 channels, 5kHz, 8-bit)");
}

// ==================== 矢量电机混合 ====================
// 参考Betaflight/ArduPilot X型四旋翼标准混控
// FR=CW, FL=CCW, BR=CCW, BL=CW
static void update_motors(void)
{
    int base_pwm;
    int64_t now = esp_timer_get_time() / 1000;

    // 根据状态确定基础PWM
    switch (g_state) {
    case STATE_IDLE:
    case STATE_ARMED:
        base_pwm = 0;
        break;

    case STATE_TAKING_OFF: {
        // 起飞：0→HOVER_PWM 线性过渡，持续2秒
        int64_t elapsed = now - g_takeoff_start;
        if (elapsed >= TAKEOFF_TIME_MS) {
            // 起飞完成，进入悬停
            g_state = STATE_HOVERING;
            g_altitude = HOVER_ALTITUDE;
            g_target_altitude = HOVER_ALTITUDE;
            base_pwm = HOVER_PWM;
            ESP_LOGI(TAG, "起飞完成，进入悬停 (%.1fm)", g_altitude / 100.0);
        } else {
            base_pwm = (int)(HOVER_PWM * elapsed / TAKEOFF_TIME_MS);
            g_altitude = (int)(HOVER_ALTITUDE * elapsed / TAKEOFF_TIME_MS);
        }
        break;
    }

    case STATE_HOVERING: {
        // 悬停状态：油门控制升降
        if (g_throttle > 0 || g_onekey_takeoff) {
            // 推油门上升，进入飞行状态
            g_state = STATE_FLYING;
            g_target_altitude = HOVER_ALTITUDE;
            ESP_LOGI(TAG, "进入飞行状态");
        }
        base_pwm = HOVER_PWM;
        break;
    }

    case STATE_FLYING: {
        // 飞行状态：油门控制高度变化
        // 油门>0 上升，油门<0 下降，油门=0 保持
        if (g_throttle > 0) {
            g_target_altitude += g_throttle * ALT_RATE_SCALE / 10;
        } else if (g_throttle < 0) {
            g_target_altitude -= (-g_throttle) * ALT_RATE_SCALE / 10;
        }
        // 限幅
        if (g_target_altitude < HOVER_ALTITUDE) g_target_altitude = HOVER_ALTITUDE;
        if (g_target_altitude > MAX_ALTITUDE) g_target_altitude = MAX_ALTITUDE;

        // 平滑逼近目标高度
        if (g_altitude < g_target_altitude) {
            g_altitude += ALT_RATE_SCALE;
            if (g_altitude > g_target_altitude) g_altitude = g_target_altitude;
        } else if (g_altitude > g_target_altitude) {
            g_altitude -= ALT_RATE_SCALE;
            if (g_altitude < g_target_altitude) g_altitude = g_target_altitude;
        }

        // 高度映射到PWM: HOVER_ALTITUDE→HOVER_PWM, MAX_ALTITUDE→MAX_PWM
        base_pwm = HOVER_PWM + (g_altitude - HOVER_ALTITUDE) * (MAX_PWM - HOVER_PWM) / (MAX_ALTITUDE - HOVER_ALTITUDE);
        if (base_pwm < HOVER_PWM) base_pwm = HOVER_PWM;
        if (base_pwm > MAX_PWM) base_pwm = MAX_PWM;
        break;
    }

    case STATE_LANDING: {
        // 降落至0.5m悬停高度
        if (g_altitude > HOVER_ALTITUDE) {
            g_altitude -= ALT_RATE_SCALE * 2;
            if (g_altitude < HOVER_ALTITUDE) g_altitude = HOVER_ALTITUDE;
            base_pwm = HOVER_PWM + (g_altitude - HOVER_ALTITUDE) * (MAX_PWM - HOVER_PWM) / (MAX_ALTITUDE - HOVER_ALTITUDE);
        } else {
            // 到达0.5m，等待最终降落指令
            g_state = STATE_HOVERING;
            g_altitude = HOVER_ALTITUDE;
            g_target_altitude = HOVER_ALTITUDE;
            base_pwm = HOVER_PWM;
            ESP_LOGI(TAG, "已降至悬停高度 (%.1fm)", g_altitude / 100.0);
        }
        break;
    }

    case STATE_LANDING_FINAL: {
        // 最终降落：0.5m→地面
        int64_t elapsed = now - g_landing_start;
        int total_time = 2000; // 2秒降落
        if (elapsed >= total_time) {
            // 降落完成
            g_state = STATE_ARMED;
            g_altitude = 0;
            g_target_altitude = 0;
            base_pwm = 0;
            ESP_LOGI(TAG, "已降落至地面");
        } else {
            // 线性降低
            int start_pwm = HOVER_PWM;
            base_pwm = start_pwm - (int)(start_pwm * elapsed / total_time);
            g_altitude = HOVER_ALTITUDE - (int)(HOVER_ALTITUDE * elapsed / total_time);
        }
        break;
    }

    case STATE_EMERGENCY:
    default:
        base_pwm = 0;
        break;
    }

    // 矢量混合：X型四旋翼标准混控
    // 俯仰正值→前倾(前进)，横滚正值→右倾，偏航正值→右转
    int pitch_pwm = g_pitch * (MAX_PWM - HOVER_PWM) / 200;
    int roll_pwm  = g_roll  * (MAX_PWM - HOVER_PWM) / 200;
    int yaw_pwm   = g_yaw   * (MAX_PWM - HOVER_PWM) / 200;

    int fr = base_pwm + pitch_pwm - roll_pwm - yaw_pwm;
    int fl = base_pwm + pitch_pwm + roll_pwm + yaw_pwm;
    int br = base_pwm - pitch_pwm - roll_pwm + yaw_pwm;
    int bl = base_pwm - pitch_pwm + roll_pwm - yaw_pwm;

    // 限幅
    if (fr < 0) fr = 0;
    if (fr > 255) fr = 255;
    if (fl < 0) fl = 0;
    if (fl > 255) fl = 255;
    if (br < 0) br = 0;
    if (br > 255) br = 255;
    if (bl < 0) bl = 0;
    if (bl > 255) bl = 255;

    // 更新PWM
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR, fr);
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FL, fl);
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_BR, br);
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_BL, bl);
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_SP, g_spray ? 255 : 0);

    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FL);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_BR);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_BL);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_SP);

    // 调试日志（每2秒）
    static int log_counter = 0;
    if (++log_counter % 100 == 0) {
        ESP_LOGI(TAG, "State:%d Alt:%d PWM:%d FR:%d FL:%d BR:%d BL:%d SP:%d",
                 g_state, g_altitude, base_pwm, fr, fl, br, bl, g_spray ? 255 : 0);
    }
}

// ==================== 飞行状态机 ====================
static void flight_state_machine(void)
{
    int64_t now = esp_timer_get_time() / 1000;

    switch (g_state) {

    case STATE_ARMED:
        // 检测油门定住1秒 → 手动起飞
        if (g_throttle > 20) {
            if (!g_throttle_held) {
                g_throttle_held = true;
                g_throttle_hold_start = now;
            } else if (now - g_throttle_hold_start >= 1000) {
                // 油门定住1秒，起飞
                g_state = STATE_TAKING_OFF;
                g_takeoff_start = now;
                g_throttle_held = false;
                ESP_LOGI(TAG, "手动起飞开始");
            }
        } else {
            g_throttle_held = false;
        }
        // 一键起飞
        if (g_onekey_takeoff) {
            g_state = STATE_TAKING_OFF;
            g_takeoff_start = now;
            g_onekey_takeoff = false;
            ESP_LOGI(TAG, "一键起飞开始");
        }
        break;

    case STATE_FLYING:
    case STATE_HOVERING:
        // 一键降落：先降到0.5m
        if (g_onekey_landing) {
            g_state = STATE_LANDING;
            g_onekey_landing = false;
            ESP_LOGI(TAG, "一键降落开始");
        }
        // 油门拉到最低 → 降落
        if (g_state == STATE_FLYING && g_throttle <= -80) {
            g_state = STATE_LANDING;
            ESP_LOGI(TAG, "油门拉低，开始降落");
        }
        break;

    case STATE_LANDING_FINAL:
        // 低于0.5m时松手（油门不再负值）→ 自动爬升回悬停
        if (g_throttle > -20 && g_altitude < HOVER_ALTITUDE && g_altitude > 0) {
            g_state = STATE_TAKING_OFF;
            g_takeoff_start = now;
            // 从当前高度起飞到悬停
            int remaining = HOVER_ALTITUDE - g_altitude;
            g_takeoff_start = now - (TAKEOFF_TIME_MS * (HOVER_ALTITUDE - remaining) / HOVER_ALTITUDE);
            ESP_LOGI(TAG, "自动爬升回悬停高度");
        }
        break;

    default:
        break;
    }
}

// ==================== UDP 指令解析 ====================
static void parse_command(const char *buf, int len)
{
    g_last_cmd_time = esp_timer_get_time() / 1000;

    char cmd[UDP_BUF_SIZE];
    strncpy(cmd, buf, len < UDP_BUF_SIZE ? len : UDP_BUF_SIZE - 1);
    cmd[len < UDP_BUF_SIZE ? len : UDP_BUF_SIZE - 1] = '\0';

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
            bool new_armed = (v != 0);
            if (new_armed != g_armed) {
                g_armed = new_armed;
                if (g_armed) {
                    g_state = STATE_ARMED;
                    g_altitude = 0;
                    g_target_altitude = 0;
                    g_throttle_held = false;
                    ESP_LOGI(TAG, "已解锁 (ARMED)");
                } else {
                    g_state = STATE_IDLE;
                    g_altitude = 0;
                    g_target_altitude = 0;
                    g_pitch = 0; g_roll = 0; g_throttle = 0; g_yaw = 0;
                    g_spray = false;
                    g_onekey_takeoff = false;
                    g_onekey_landing = false;
                    g_throttle_held = false;
                    ESP_LOGI(TAG, "已上锁 (DISARMED)");
                }
            }
        } else if (strcmp(key, "PIT") == 0) {
            g_pitch = (v < -100) ? -100 : ((v > 100) ? 100 : v);
        } else if (strcmp(key, "ROL") == 0) {
            g_roll = (v < -100) ? -100 : ((v > 100) ? 100 : v);
        } else if (strcmp(key, "THR") == 0) {
            g_throttle = (v < -100) ? -100 : ((v > 100) ? 100 : v);
        } else if (strcmp(key, "YAW") == 0) {
            g_yaw = (v < -100) ? -100 : ((v > 100) ? 100 : v);
        } else if (strcmp(key, "SPR") == 0) {
            g_spray = (v != 0);
        } else if (strcmp(key, "TAKEOFF") == 0 && v != 0) {
            g_onekey_takeoff = true;
            ESP_LOGI(TAG, "收到一键起飞指令");
        } else if (strcmp(key, "LAND") == 0 && v != 0) {
            if (g_state == STATE_LANDING || g_state == STATE_HOVERING) {
                // 已在0.5m或正在降落，执行最终降落
                g_state = STATE_LANDING_FINAL;
                g_landing_start = esp_timer_get_time() / 1000;
                ESP_LOGI(TAG, "收到最终降落指令");
            } else {
                g_onekey_landing = true;
                ESP_LOGI(TAG, "收到一键降落指令");
            }
        }

        token = strtok_r(NULL, ";", &saveptr1);
    }

    // 运行状态机
    flight_state_machine();
    update_motors();
}

// ==================== 心跳超时检测任务 ====================
static void heartbeat_task(void *pvParameters)
{
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(500));

        if (g_state == STATE_IDLE || g_state == STATE_EMERGENCY) continue;

        int64_t now = esp_timer_get_time() / 1000;
        if (now - g_last_cmd_time > CMD_TIMEOUT_MS) {
            ESP_LOGW(TAG, "心跳超时（%.1fs无指令），紧急停机",
                     (float)(now - g_last_cmd_time) / 1000.0);
            g_state = STATE_EMERGENCY;
            g_armed = false;
            g_altitude = 0;
            g_target_altitude = 0;
            g_pitch = 0; g_roll = 0; g_throttle = 0; g_yaw = 0;
            g_spray = false;
            g_onekey_takeoff = false;
            g_onekey_landing = false;
            update_motors();
        }
    }
}

// ==================== UDP 接收任务 ====================
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
            parse_command(rx_buf, len);
        }
    }

    close(sock);
    vTaskDelete(NULL);
}

// ==================== WiFi 事件处理 ====================
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                                int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_AP_STACONNECTED) {
        wifi_event_ap_staconnected_t *event = (wifi_event_ap_staconnected_t *)event_data;
        ESP_LOGI(TAG, "手机已连接: MAC=" MACSTR, MAC2STR(event->mac));
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_AP_STADISCONNECTED) {
        ESP_LOGI(TAG, "手机已断开，紧急停机");
        g_state = STATE_EMERGENCY;
        g_armed = false;
        g_altitude = 0;
        g_target_altitude = 0;
        g_pitch = 0; g_roll = 0; g_throttle = 0; g_yaw = 0;
        g_spray = false;
        g_onekey_takeoff = false;
        g_onekey_landing = false;
        update_motors();
    }
}

static void wifi_init_ap(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_ap();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT,
        ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL));

    wifi_config_t wifi_config = {
        .ap = {
            .ssid = WIFI_SSID,
            .ssid_len = strlen(WIFI_SSID),
            .channel = WIFI_CHANNEL,
            .password = WIFI_PASSWORD,
            .max_connection = WIFI_MAX_CONN,
            .authmode = WIFI_AUTH_OPEN,
        },
    };

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());

    ESP_LOGI(TAG, "WiFi AP 已启动: SSID=%s, 信道=%d", WIFI_SSID, WIFI_CHANNEL);
}

// ==================== LED自检 ====================
static void led_self_test(void)
{
    ESP_LOGI(TAG, "========== LED自检开始 ==========");
    const char *test_names[] = {"FR(GPIO1)", "FL(GPIO4)", "BR(GPIO21)", "BL(GPIO12)", "SP(GPIO18)"};

    for (int i = 0; i < 5; i++) {
        ESP_LOGI(TAG, "自检: 点亮 %s", test_names[i]);
        ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR + i, 255);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR + i);
        vTaskDelay(pdMS_TO_TICKS(500));
        ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR + i, 0);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR + i);
        vTaskDelay(pdMS_TO_TICKS(200));
    }

    ESP_LOGI(TAG, "自检: 全部点亮");
    for (int i = 0; i < 5; i++) {
        ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR + i, 255);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR + i);
    }
    vTaskDelay(pdMS_TO_TICKS(500));
    for (int i = 0; i < 5; i++) {
        ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR + i, 0);
        ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CH_FR + i);
    }

    ESP_LOGI(TAG, "========== LED自检完成 ==========");
}

// ==================== 主函数 ====================
void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ledc_init();
    update_motors();
    led_self_test();

    wifi_init_ap();

    g_last_cmd_time = esp_timer_get_time() / 1000;

    xTaskCreate(udp_server_task, "udp_server", 4096, NULL, 5, NULL);
    xTaskCreate(heartbeat_task, "heartbeat", 2048, NULL, 3, NULL);

    ESP_LOGI(TAG, "护花使者 v2 - 无人机验证平台已就绪");
    ESP_LOGI(TAG, "飞行状态机: IDLE→ARMED→TAKEOFF→HOVERING→FLYING");
    ESP_LOGI(TAG, "四旋翼引脚: FR=GPIO1, FL=GPIO4, BR=GPIO21, BL=GPIO12");
    ESP_LOGI(TAG, "请用手机连接WiFi: %s", WIFI_SSID);
}