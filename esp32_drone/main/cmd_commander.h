/**
 * cmd_commander.h - 飞行指挥层（对应 PX4 commander）
 * 护花使者 ESP32-S3 飞控
 * 职责：飞行状态机、解锁逻辑、摇杆→设定值映射、模拟高度、安全通知
 */
#ifndef CMD_COMMANDER_H
#define CMD_COMMANDER_H

#include "drone_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化指挥层
 */
void cmd_init(void);

/**
 * @brief 指挥层节拍（100Hz，commander_task 调用）
 * 读取遥控输入 → 状态机 → 生成控制设定值 → 发布给控制器
 */
void cmd_run(void);

/**
 * @brief 心跳超时通知（heartbeat_task 调用）→ 紧急停机
 */
void cmd_notify_heartbeat_timeout(void);

/**
 * @brief WiFi 断开通知（wifi 事件回调调用）→ 紧急停机
 */
void cmd_notify_wifi_disconnected(void);

/**
 * @brief IMU 无效通知（imu_task 调用）
 * 飞行中 → 紧急停机；已解锁未起飞 → 上锁
 */
void cmd_notify_imu_invalid(void);

/**
 * @brief IMU 恢复通知（imu_task 调用，解除解锁禁令）
 */
void cmd_notify_imu_valid(void);

#ifdef __cplusplus
}
#endif

#endif /* CMD_COMMANDER_H */
