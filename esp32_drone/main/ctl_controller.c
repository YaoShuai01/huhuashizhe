/**
 * ctl_controller.c - 串级姿态控制器
 * 护花使者 ESP32-S3 飞控
 *
 * 控制链：
 *   设定值(倾角/偏航速率/推力) → 外环姿态P → 期望角速率
 *     → 内环速率PID → 扭矩 → 归一化混控 → 电机PWM
 *
 * 非飞行状态（IDLE/ARMED/EMERGENCY）不输出姿态控制，电机保持 1ms 停转。
 */
#include <string.h>
#include <math.h>
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "ctl_controller.h"
#include "mix_mixer.h"
#include "out_pwm.h"
#include "prm_params.h"

static const char *TAG = "CTL";

// 设定值邮箱（commander 写，ctl 读）
static ctl_setpoint_t s_sp;
static SemaphoreHandle_t s_sp_mutex = NULL;

// 速率环状态
static float s_i_pitch = 0.0f, s_i_roll = 0.0f;
static float s_prev_gyro_pitch = 0.0f, s_prev_gyro_roll = 0.0f;
static bool  s_prev_valid = false;

// 是否处于可控制飞行的状态
static inline bool ctl_state_active(flight_state_t st)
{
    return (st == ST_TAKING_OFF || st == ST_HOVERING || st == ST_FLYING ||
            st == ST_LANDING || st == ST_LANDING_FINAL);
}

void ctl_init(void)
{
    s_sp_mutex = xSemaphoreCreateMutex();
    memset(&s_sp, 0, sizeof(s_sp));
    ctl_reset_integrators();
    ESP_LOGI(TAG, "串级控制器初始化 (外环姿态P + 内环速率PID)");
}

void ctl_set_setpoint(const ctl_setpoint_t *sp)
{
    if (s_sp_mutex == NULL) return;
    xSemaphoreTake(s_sp_mutex, portMAX_DELAY);
    memcpy(&s_sp, sp, sizeof(s_sp));
    xSemaphoreGive(s_sp_mutex);
}

void ctl_reset_integrators(void)
{
    s_i_pitch = 0.0f;
    s_i_roll = 0.0f;
    s_prev_valid = false;
}

void ctl_step(const attitude_data_t *att)
{
    const prm_param_t *p = prm_get();
    float dt = 1.0f / (float)p->ctl_hz;

    // 读取最新设定值
    if (s_sp_mutex == NULL) return;
    ctl_setpoint_t sp;
    xSemaphoreTake(s_sp_mutex, portMAX_DELAY);
    memcpy(&sp, &s_sp, sizeof(s_sp));
    xSemaphoreGive(s_sp_mutex);

    // 喷洒输出（任何时候跟随设定值，保持 v3 兼容行为）
    out_set_spray(sp.spray_level);

    // 非飞行状态：电机 1ms，积分清零
    if (!ctl_state_active(sp.state)) {
        ctl_reset_integrators();
        float zero[4] = {0.0f, 0.0f, 0.0f, 0.0f};
        out_set_motors(zero);
        return;
    }

    // ============ 外环：姿态角 P 控制 → 期望角速率 ============
    float sp_pitch_rate = p->att_p_pitch * (sp.tilt_pitch - att->pitch);
    float sp_roll_rate  = p->att_p_roll  * (sp.tilt_roll  - att->roll);
    float sp_yaw_rate   = sp.yaw_rate_cmd;    // 偏航直接用速率设定

    // ============ 内环：角速率 PID → 扭矩 ============
    float e_pitch = sp_pitch_rate - att->pitch_rate;
    float e_roll  = sp_roll_rate  - att->roll_rate;
    float e_yaw   = sp_yaw_rate   - att->yaw_rate;

    // D 项作用在测量微分（高通，抗突变）
    float d_pitch = 0.0f, d_roll = 0.0f;
    if (s_prev_valid) {
        d_pitch = (att->pitch_rate - s_prev_gyro_pitch) / dt;
        d_roll  = (att->roll_rate  - s_prev_gyro_roll)  / dt;
    }
    s_prev_gyro_pitch = att->pitch_rate;
    s_prev_gyro_roll  = att->roll_rate;
    s_prev_valid = true;

    // 积分（限幅；仅在控制有效且误差与扭矩同向时积分，防饱和积分）
    s_i_pitch += e_pitch * dt;
    s_i_roll  += e_roll  * dt;
    if (s_i_pitch >  p->rate_i_limit) s_i_pitch =  p->rate_i_limit;
    if (s_i_pitch < -p->rate_i_limit) s_i_pitch = -p->rate_i_limit;
    if (s_i_roll  >  p->rate_i_limit) s_i_roll  =  p->rate_i_limit;
    if (s_i_roll  < -p->rate_i_limit) s_i_roll  = -p->rate_i_limit;

    float tau_pitch = p->rate_p_pitch * e_pitch + p->rate_i_pitch * s_i_pitch - p->rate_d_pitch * d_pitch;
    float tau_roll  = p->rate_p_roll  * e_roll  + p->rate_i_roll  * s_i_roll  - p->rate_d_roll  * d_roll;
    float tau_yaw   = p->yaw_rate_p * e_yaw;

    // 扭矩 → 混控单位（归一化 ±1）
    float m_p = tau_pitch * p->torque_scale;
    float m_r = tau_roll  * p->torque_scale;
    float m_y = tau_yaw   * p->torque_scale;

    // ============ 混控 + 输出 ============
    // IMU 绕 Z 轴 +90° 旋回机体系后，本机俯仰正方向与混控约定相反：
    // 取反后，手压机头时前电机加速回正，推杆向前时后电机加速低头前进。
    float motor[4];
    mix_apply(sp.thrust_cmd, m_r, -m_p, m_y, motor);
    out_set_motors(motor);

    // 调试日志（每 1 秒）
    static uint32_t log_cnt = 0;
    if (++log_cnt >= p->ctl_hz) {
        log_cnt = 0;
        ESP_LOGI(TAG, "St:%d THR:%.2f R:%.1f P:%.1f Y:%.1f | dR:%.1f dP:%.1f dY:%.1f | M[%.2f %.2f %.2f %.2f]",
                 sp.state, sp.thrust_cmd,
                 att->roll * 57.2958f, att->pitch * 57.2958f, att->yaw * 57.2958f,
                 att->roll_rate, att->pitch_rate, att->yaw_rate,
                 motor[0], motor[1], motor[2], motor[3]);
    }
}
