/**
 * prm_params.c - PX4 风格参数表默认值
 * 护花使者 ESP32-S3 飞控
 * 注意：PID 增益为地面整定初始值，需拆桨试飞逐步调整
 */
#include "prm_params.h"

static const prm_param_t s_prm = {
    // 姿态环（外环 P）
    .att_p_pitch      = 5.0f,
    .att_p_roll       = 5.0f,
    .max_tilt_rad     = 0.4363f,   // 25°

    // 速率环（内环 PID）
    .rate_p_pitch     = 0.15f,
    .rate_i_pitch     = 0.15f,
    .rate_d_pitch     = 0.003f,
    .rate_p_roll      = 0.15f,
    .rate_i_roll      = 0.15f,
    .rate_d_roll      = 0.003f,
    .rate_i_limit     = 0.25f,
    .yaw_rate_p       = 0.20f,
    .torque_scale     = 1.0f,

    // 遥控输入
    .rc_deadband         = 8.0f,
    .max_yaw_rate_rad_s  = 2.5f,

    // 高度模拟（无气压计）
    .hover_thrust     = 0.13f,     // 对应原 HOVER_PWM 35/255
    .alt_rate_units_s = 200.0f,    // 满杆 2m/秒（模拟）
    .hover_alt        = 50.0f,     // 0.5m
    .max_alt          = 200.0f,    // 2m

    // Mahony
    .mahony_beta      = 0.2f,

    // 输出
    .esc_min_us       = 1000,
    .esc_max_us       = 2000,
    .pump_duty        = {0, 115, 140, 166, 191, 224, 255},  // 45%~100%

    // 频率
    .imu_hz           = 1000,
    .ctl_hz           = 250,

    // 安全
    .cmd_timeout_ms   = 3000,
    .imu_fail_frames  = 20,
};

const prm_param_t *prm_get(void)
{
    return &s_prm;
}
