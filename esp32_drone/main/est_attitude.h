/**
 * est_attitude.h - Mahony 姿态解算（对应 PX4 attitude_estimator_q）
 * 护花使者 ESP32-S3 飞控
 * 输入：1kHz IMU 数据；输出：250Hz 姿态角 + 体轴角速度
 */
#ifndef EST_ATTITUDE_H
#define EST_ATTITUDE_H

#include "drone_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化姿态估计器
 */
void est_attitude_init(void);

/**
 * @brief 复位姿态参考（上锁/解锁时调用，置单位四元数）
 */
void est_attitude_reset(void);

/**
 * @brief 每帧 IMU 数据调用（1kHz），内部执行 Mahony 融合
 * @param imu IMU 原始数据（已去偏移）
 */
void est_attitude_update(const imu_data_t *imu);

/**
 * @brief 获取最新姿态（250Hz 发布，线程安全）
 * @param out 输出姿态
 */
void est_attitude_get(attitude_data_t *out);

#ifdef __cplusplus
}
#endif

#endif /* EST_ATTITUDE_H */
