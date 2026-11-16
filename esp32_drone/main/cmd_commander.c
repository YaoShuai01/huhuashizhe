/**
 * cmd_commander.c - 飞行指挥层
 * 护花使者 ESP32-S3 飞控
 *
 * 状态机（与 v3 语义一致）：
 *   IDLE → ARMED → TAKING_OFF(0→0.5m,2s) → HOVERING
 *   HOVERING ↔ FLYING(油门控制高度)
 *   FLYING/HOVERING → LANDING(→0.5m) → LANDING_FINAL(→地面)
 *   LANDING_FINAL(低于0.5m松手) → 自动爬升回HOVERING
 *   任意飞行态 → EMERGENCY（心跳超时/WiFi断开/IMU失效）
 */
#include <string.h>
#include <math.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "cmd_commander.h"
#include "rc_udp.h"
#include "ctl_controller.h"
#include "est_attitude.h"
#include "out_pwm.h"
#include "prm_params.h"

static const char *TAG = "CMD";

// 状态与设定值（互斥锁保护，支持跨任务通知）
static flight_state_t s_state = ST_IDLE;
static bool  s_armed = false;
static float s_alt = 0.0f;          // 当前模拟高度
static float s_alt_target = 0.0f;   // 目标模拟高度
static int64_t s_takeoff_start = 0;
static int64_t s_landing_start = 0;
static int64_t s_throttle_hold_start = 0;
static bool  s_throttle_held = false;
static int   s_spray = 0;
static ctl_setpoint_t s_sp;
static SemaphoreHandle_t s_cmd_mutex = NULL;

// IMU 有效标志（imu_task 更新）
static bool s_imu_valid = true;

#define TAKEOFF_TIME_MS     2000
#define LANDING_FINAL_MS    2000
#define THROTTLE_HOLD_MS    1000
#define THROTTLE_TAKEOFF_TH 20      // 手动起飞油门阈值
#define ALT_APPROACH_RATE   100.0f  // 模拟高度逼近速率(单位/s)
#define LANDING_DESC_RATE   200.0f  // 降落下降速率(单位/s)

// ==================== 内部工具 ====================

// 死区（比例保持）：|v|≤db → 0，超出后从 db+1 起线性
static int deadband(int v, int db)
{
    if (v > db) return v - db;
    if (v < -db) return v + db;
    return 0;
}

// 高度 → 总推力（悬停高度→悬停推力，最大高度→最大推力）
static float thrust_from_alt(float alt)
{
    const prm_param_t *p = prm_get();
    float t = p->hover_thrust +
              (alt - p->hover_alt) / (p->max_alt - p->hover_alt) * (1.0f - p->hover_thrust);
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;
    return t;
}

// 立即进入紧急状态（任何任务可调用）
static void enter_emergency(const char *reason)
{
    bool do_it = false;
    if (s_cmd_mutex) {
        xSemaphoreTake(s_cmd_mutex, portMAX_DELAY);
        // IDLE（未解锁未上电）不需要进入紧急态，避免无谓锁定
        if (s_state != ST_EMERGENCY && s_state != ST_IDLE) {
            s_state = ST_EMERGENCY;
            s_armed = false;
            s_alt = 0.0f;
            s_alt_target = 0.0f;
            s_throttle_held = false;
            s_spray = 0;
            do_it = true;
            ESP_LOGW(TAG, "紧急停机: %s", reason);
        }
        xSemaphoreGive(s_cmd_mutex);
    }
    if (do_it) {
        // 立即发布安全设定值并执行紧急输出
        ctl_setpoint_t sp;
        xSemaphoreTake(s_cmd_mutex, portMAX_DELAY);
        memset(&sp, 0, sizeof(sp));
        sp.state = ST_EMERGENCY;
        xSemaphoreGive(s_cmd_mutex);
        ctl_set_setpoint(&sp);
        ctl_reset_integrators();
        out_emergency();
    }
}

// 发布当前状态对应的设定值（须已持锁）
static void publish_setpoint_locked(void)
{
    memset(&s_sp, 0, sizeof(s_sp));
    s_sp.state = s_state;
    s_sp.armed = s_armed;
    s_sp.spray_level = s_spray;

    switch (s_state) {
    case ST_TAKING_OFF:
    case ST_HOVERING:
    case ST_FLYING:
    case ST_LANDING:
    case ST_LANDING_FINAL:
        s_sp.thrust_cmd = thrust_from_alt(s_alt);   // 倾角/偏航速率由 cmd_run 摇杆映射填充
        s_sp.alt_sim = s_alt;
        break;
    default:
        s_sp.thrust_cmd = 0.0f;
        break;
    }
}

// ==================== 状态机（100Hz） ====================
// 注意：本函数假设已持有 s_cmd_mutex，且 rc 已拷贝到 local
static void state_machine_run(rc_input_t *rc, int64_t now)
{
    const prm_param_t *p = prm_get();

    switch (s_state) {

    case ST_IDLE:
        // ARM:1 → 解锁（IMU 有效才允许）
        if (rc->arm) {
            if (!s_imu_valid) {
                ESP_LOGW(TAG, "解锁被拒绝：IMU 无效");
            } else {
                s_state = ST_ARMED;
                s_armed = true;
                s_alt = 0.0f;
                s_alt_target = 0.0f;
                s_throttle_held = false;
                est_attitude_reset();
                ESP_LOGI(TAG, "已解锁 (ARMED)");
            }
        }
        break;

    case ST_ARMED:
        if (!rc->arm) {
            s_state = ST_IDLE;
            s_armed = false;
            est_attitude_reset();
            ESP_LOGI(TAG, "已上锁 (DISARMED)");
            break;
        }
        // 手动起飞：油门定住 1 秒
        if (rc->throttle > THROTTLE_TAKEOFF_TH) {
            if (!s_throttle_held) {
                s_throttle_held = true;
                s_throttle_hold_start = now;
            } else if (now - s_throttle_hold_start >= THROTTLE_HOLD_MS) {
                s_state = ST_TAKING_OFF;
                s_takeoff_start = now;
                s_throttle_held = false;
                ESP_LOGI(TAG, "手动起飞开始");
            }
        } else {
            s_throttle_held = false;
        }
        // 一键起飞
        if (rc->takeoff_pending) {
            rc->takeoff_pending = false;
            s_state = ST_TAKING_OFF;
            s_takeoff_start = now;
            ESP_LOGI(TAG, "一键起飞开始");
        }
        break;

    case ST_TAKING_OFF: {
        // 0→悬停高度，2 秒线性爬升
        int64_t elapsed = now - s_takeoff_start;
        if (elapsed >= TAKEOFF_TIME_MS) {
            s_state = ST_HOVERING;
            s_alt = p->hover_alt;
            s_alt_target = p->hover_alt;
            ESP_LOGI(TAG, "起飞完成，进入悬停 (%.1fm)", s_alt / 100.0f);
        } else {
            s_alt = p->hover_alt * (float)elapsed / TAKEOFF_TIME_MS;
        }
        break;
    }

    case ST_HOVERING:
        // 推油门上升，进入飞行状态
        if (rc->throttle > 0) {
            s_state = ST_FLYING;
            s_alt_target = p->hover_alt;
            ESP_LOGI(TAG, "进入飞行状态");
        }
        break;

    case ST_FLYING: {
        // 油门控制目标高度
        int thr_db = deadband(rc->throttle, (int)p->rc_deadband);
        float dt = 1.0f / 100.0f;   // commander 100Hz
        s_alt_target += (float)thr_db / 100.0f * p->alt_rate_units_s * dt;
        if (s_alt_target < p->hover_alt) s_alt_target = p->hover_alt;
        if (s_alt_target > p->max_alt)   s_alt_target = p->max_alt;

        // 高度平滑逼近目标
        if (s_alt < s_alt_target) {
            s_alt += ALT_APPROACH_RATE * dt;
            if (s_alt > s_alt_target) s_alt = s_alt_target;
        } else if (s_alt > s_alt_target) {
            s_alt -= ALT_APPROACH_RATE * dt;
            if (s_alt < s_alt_target) s_alt = s_alt_target;
        }
        break;
    }

    case ST_LANDING:
        // 降至悬停高度 → HOVERING
        s_alt -= LANDING_DESC_RATE * (1.0f / 100.0f);
        if (s_alt <= p->hover_alt) {
            s_state = ST_HOVERING;
            s_alt = p->hover_alt;
            s_alt_target = p->hover_alt;
            ESP_LOGI(TAG, "已降至悬停高度 (%.1fm)", s_alt / 100.0f);
        }
        break;

    case ST_LANDING_FINAL: {
        // 0.5m→地面，2 秒线性降落
        int64_t elapsed = now - s_landing_start;
        if (elapsed >= LANDING_FINAL_MS) {
            s_state = ST_ARMED;
            s_alt = 0.0f;
            s_alt_target = 0.0f;
            ESP_LOGI(TAG, "已降落至地面");
        } else {
            s_alt = p->hover_alt * (1.0f - (float)elapsed / LANDING_FINAL_MS);
        }
        break;
    }

    case ST_EMERGENCY:
        // 仅可通过 ARM:0 退出（上锁）
        if (!rc->arm) {
            s_state = ST_IDLE;
            s_armed = false;
            est_attitude_reset();
            ESP_LOGI(TAG, "紧急状态已解除 (IDLE)");
        }
        break;

    default:
        break;
    }

    // ---------- 横跨状态的指令处理 ----------

    // 一键降落（v3 语义：悬停/降落中 → 直接最终降落；飞行中 → 先降0.5m）
    if (rc->land_pending && s_state != ST_EMERGENCY && s_state != ST_IDLE && s_state != ST_ARMED) {
        rc->land_pending = false;
        if (s_state == ST_LANDING || s_state == ST_HOVERING) {
            s_state = ST_LANDING_FINAL;
            s_landing_start = now;
            ESP_LOGI(TAG, "收到最终降落指令");
        } else if (s_state == ST_FLYING || s_state == ST_TAKING_OFF) {
            s_state = ST_LANDING;
            s_landing_start = now;
            ESP_LOGI(TAG, "一键降落开始");
        }
    }

    // 飞行中油门拉最低 → 自动降落
    if (s_state == ST_FLYING && rc->throttle <= -80) {
        s_state = ST_LANDING;
        ESP_LOGI(TAG, "油门拉低，开始降落");
    }

    // 最终降落低于0.5m时松手 → 自动爬升回悬停
    if (s_state == ST_LANDING_FINAL && rc->throttle > -20 && s_alt > 0.0f && s_alt < p->hover_alt) {
        s_state = ST_TAKING_OFF;
        // 从当前高度继续起飞到悬停（按已耗时折算）
        s_takeoff_start = now - (int64_t)(TAKEOFF_TIME_MS * s_alt / p->hover_alt);
        ESP_LOGI(TAG, "自动爬升回悬停高度");
    }

    // 上锁（任何状态）
    if (!rc->arm && s_armed) {
        s_state = ST_IDLE;
        s_armed = false;
        s_alt = 0.0f;
        s_alt_target = 0.0f;
        s_spray = 0;
        s_throttle_held = false;
        est_attitude_reset();
        ESP_LOGI(TAG, "已上锁 (DISARMED)");
    }
}

// ==================== 对外接口 ====================

void cmd_init(void)
{
    s_cmd_mutex = xSemaphoreCreateMutex();
    memset(&s_sp, 0, sizeof(s_sp));
    ESP_LOGI(TAG, "指挥层初始化 (状态机 100Hz)");
}

void cmd_run(void)
{
    const prm_param_t *p = prm_get();
    int64_t now = esp_timer_get_time() / 1000;

    // 读取遥控输入
    rc_input_t rc;
    rc_get_input(&rc);

    xSemaphoreTake(s_cmd_mutex, portMAX_DELAY);

    // 喷洒挡位跟随
    s_spray = rc.spray;

    // 状态机
    state_machine_run(&rc, now);

    // 基础设定值（状态/推力/高度），随后填充摇杆映射
    publish_setpoint_locked();

    // 摇杆 → 目标倾角/偏航速率（仅飞行状态有效，非飞行态保持 0）
    if (s_state == ST_TAKING_OFF || s_state == ST_HOVERING ||
        s_state == ST_FLYING || s_state == ST_LANDING || s_state == ST_LANDING_FINAL) {
        int pit_db = deadband(rc.pitch, (int)p->rc_deadband);
        int rol_db = deadband(rc.roll,  (int)p->rc_deadband);
        int yaw_db = deadband(rc.yaw,   (int)p->rc_deadband);
        s_sp.tilt_pitch = (float)pit_db / 100.0f * p->max_tilt_rad;
        s_sp.tilt_roll  = (float)rol_db / 100.0f * p->max_tilt_rad;
        s_sp.yaw_rate_cmd = (float)yaw_db / 100.0f * p->max_yaw_rate_rad_s;
    }

    xSemaphoreGive(s_cmd_mutex);

    // 发布给控制器
    ctl_set_setpoint(&s_sp);
}

void cmd_notify_heartbeat_timeout(void)
{
    enter_emergency("心跳超时(3s无指令)");
}

void cmd_notify_wifi_disconnected(void)
{
    enter_emergency("WiFi 断开");
}

void cmd_notify_imu_invalid(void)
{
    xSemaphoreTake(s_cmd_mutex, portMAX_DELAY);
    bool was_valid = s_imu_valid;
    s_imu_valid = false;
    bool in_flight = (s_state == ST_TAKING_OFF || s_state == ST_HOVERING ||
                      s_state == ST_FLYING || s_state == ST_LANDING ||
                      s_state == ST_LANDING_FINAL);
    bool in_armed = (s_state == ST_ARMED);
    xSemaphoreGive(s_cmd_mutex);

    if (was_valid) {
        if (in_flight) {
            enter_emergency("IMU 数据失效(飞行中)");
        } else if (in_armed) {
            // 已解锁未起飞：自动上锁
            xSemaphoreTake(s_cmd_mutex, portMAX_DELAY);
            s_state = ST_IDLE;
            s_armed = false;
            s_throttle_held = false;
            xSemaphoreGive(s_cmd_mutex);
            ESP_LOGW(TAG, "IMU 失效，已自动上锁");
            ctl_reset_integrators();
            out_emergency();
        }
    }
}

void cmd_notify_imu_valid(void)
{
    xSemaphoreTake(s_cmd_mutex, portMAX_DELAY);
    if (!s_imu_valid) {
        s_imu_valid = true;
        ESP_LOGI(TAG, "IMU 数据恢复，解除解锁禁令");
    }
    xSemaphoreGive(s_cmd_mutex);
}
