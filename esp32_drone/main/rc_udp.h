/**
 * rc_udp.h - UDP 遥控输入（对应 PX4 rc_update）
 * 护花使者 ESP32-S3 飞控
 * 协议：UDP 8888 端口，K:V;K:V 格式，50Hz 摇杆 + 一次性指令
 */
#ifndef RC_UDP_H
#define RC_UDP_H

#include "drone_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化 UDP 接收模块（创建互斥锁）
 */
void rc_init(void);

/**
 * @brief 启动 UDP 服务器任务（端口 8888）
 */
void rc_udp_task_start(void);

/**
 * @brief 获取最新遥控输入（commander 调用，互斥锁保护）
 */
void rc_get_input(rc_input_t *out);

#ifdef __cplusplus
}
#endif

#endif /* RC_UDP_H */
