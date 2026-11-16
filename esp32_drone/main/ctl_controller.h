/**
 * ctl_controller.h - 串级姿态控制器（对应 PX4 mc_att_control / mc_rate_control）
 * 护花使者 ESP32-S3 飞控
 * 外环：姿态角 P 控制 → 期望角速率
 * 内环：角速率 PID → 三轴扭矩（yaw 仅 P）
 */
#ifndef CTL_CONTROLLER_H
#define CTL_CONTROLLER_H

#include "drone_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化控制器
 */
void ctl_init(void);

/**
 * @brief 写入控制设定值（commander 调用，互斥锁保护）
 */
void ctl_set_setpoint(const ctl_setpoint_t *sp);

/**
 * @brief 控制步进（250Hz 调用）：姿态环 + 速率环 + 混控 + 输出
 * @param att 最新姿态估计
 */
void ctl_step(const attitude_data_t *att);

/**
 * @brief 清除积分器（失锁/紧急/非飞行状态）
 */
void ctl_reset_integrators(void);

#ifdef __cplusplus
}
#endif

#endif /* CTL_CONTROLLER_H */
