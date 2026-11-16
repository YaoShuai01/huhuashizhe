/**
 * prm_params.h - PX4 风格参数表（编译期默认值）
 * 护花使者 ESP32-S3 飞控
 */
#ifndef PRM_PARAMS_H
#define PRM_PARAMS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    // ---------- 姿态环（外环 P，PX4 MC_*_P） ----------
    float att_p_pitch;         // 俯仰角 P 增益
    float att_p_roll;          // 横滚角 P 增益
    float max_tilt_rad;        // 最大倾角 rad（25°≈0.4363）

    // ---------- 速率环（内环 PID，PX4 MC_*RATE_P/I/D） ----------
    float rate_p_pitch, rate_i_pitch, rate_d_pitch;
    float rate_p_roll,  rate_i_roll,  rate_d_roll;
    float rate_i_limit;        // 积分限幅
    float yaw_rate_p;          // 偏航角速率 P（无磁力计，仅 P）
    float torque_scale;        // 扭矩→混控单位换算（默认1.0，PID输出已归一化）

    // ---------- 遥控输入 ----------
    float rc_deadband;         // 摇杆死区（-100..100 域）
    float max_yaw_rate_rad_s;  // 最大偏航角速率 rad/s

    // ---------- 高度模拟（无气压计） ----------
    float hover_thrust;        // 悬停推力 0..1
    float alt_rate_units_s;    // 满杆高度变化速率（内部单位/秒）
    float hover_alt;           // 悬停高度（内部单位）
    float max_alt;             // 最大高度（内部单位）

    // ---------- Mahony 姿态解算 ----------
    float mahony_beta;         // 互补滤波系数

    // ---------- 输出 ----------
    uint16_t esc_min_us;       // 电调最小脉宽 us（1.0ms）
    uint16_t esc_max_us;       // 电调最大脉宽 us（2.0ms）
    uint8_t  pump_duty[7];     // 水泵 6 挡占空比 8bit（0=关）

    // ---------- 频率 ----------
    uint32_t imu_hz;           // IMU 采样频率
    uint32_t ctl_hz;           // 控制环频率

    // ---------- 安全 ----------
    uint32_t cmd_timeout_ms;   // 心跳超时 ms
    uint32_t imu_fail_frames;  // 连续读失败帧数阈值
} prm_param_t;

// 获取参数表（编译期默认值）
const prm_param_t *prm_get(void);

#ifdef __cplusplus
}
#endif

#endif /* PRM_PARAMS_H */
