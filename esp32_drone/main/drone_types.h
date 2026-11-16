/**
 * drone_types.h - 共享数据类型（对应 PX4 uORB 消息定义）
 * 护花使者 ESP32-S3 飞控（PX4 工程思维重构）
 */
#ifndef DRONE_TYPES_H
#define DRONE_TYPES_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ==================== 飞行状态枚举（与 v3 语义一致） ====================
typedef enum {
    ST_IDLE = 0,       // 未解锁
    ST_ARMED,          // 已解锁，等待起飞
    ST_TAKING_OFF,     // 起飞中 (0→0.5m)
    ST_HOVERING,       // 悬停在0.5m
    ST_FLYING,         // 飞行中 (>0.5m)
    ST_LANDING,        // 降落中 (→0.5m)
    ST_LANDING_FINAL,  // 最终降落 (→地面)
    ST_EMERGENCY       // 紧急停机
} flight_state_t;

// ==================== IMU 原始数据（imu_task 产出, 1kHz） ====================
typedef struct {
    float ax, ay, az;        // 加速度 g
    float gx, gy, gz;        // 角速度 rad/s（体轴）
    bool  valid;             // 数据有效（I2C 读取成功）
    uint64_t timestamp_us;   // 时间戳
} imu_data_t;

// ==================== 姿态估计（est 产出, 250Hz） ====================
typedef struct {
    float roll, pitch, yaw;  // 姿态角 rad
    float roll_rate, pitch_rate, yaw_rate;  // 体轴角速度 rad/s
    bool  valid;
    uint64_t timestamp_us;
} attitude_data_t;

// ==================== 控制设定值（commander 产出, ctl 消费） ====================
typedef struct {
    flight_state_t state;    // 当前状态
    bool  armed;             // 解锁标志
    float tilt_pitch;        // 目标俯仰角 rad（前倾为正）
    float tilt_roll;         // 目标横滚角 rad（右倾为正）
    float yaw_rate_cmd;      // 目标偏航角速度 rad/s（右转为正）
    float thrust_cmd;        // 总推力 0..1
    float alt_sim;           // 模拟高度（内部单位）
    int   spray_level;       // 喷洒挡位 0=关 1~6=力度
} ctl_setpoint_t;

// ==================== 遥控原始输入（udp 任务产出, 50Hz） ====================
typedef struct {
    int   pitch, roll, throttle, yaw;   // 摇杆 -100..100
    int   spray;                        // 喷洒 0..6
    bool  arm;                          // 解锁 0/1（电平）
    bool  takeoff_pending;              // 一键起飞待处理（commander 处理后清除）
    bool  land_pending;                 // 一键降落待处理（commander 处理后清除）
    uint32_t last_rx_ms;                // 最后收到指令的时间(ms)
} rc_input_t;

#ifdef __cplusplus
}
#endif

#endif /* DRONE_TYPES_H */
