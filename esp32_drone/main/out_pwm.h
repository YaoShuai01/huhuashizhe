/**
 * out_pwm.h - LEDC PWM 输出（对应 PX4 actuator_outputs）
 * 护花使者 ESP32-S3 飞控
 * 电调：50Hz/14bit，1ms 停 ~ 2ms 最大；水泵：5kHz/8bit
 */
#ifndef OUT_PWM_H
#define OUT_PWM_H

#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief 初始化 GPIO + LEDC 定时器/通道
 * 上电立即输出 1ms 最低油门到所有电调（防电调进入校准/编程模式），并做信号自检
 */
esp_err_t out_init(void);

/**
 * @brief 设置 4 电机输出（归一化 0..1 → 脉宽 1..2ms）
 * @param motor[4] {FR, FL, BR, BL}
 */
void out_set_motors(const float motor[4]);

/**
 * @brief 设置水泵挡位（0=关, 1~6=力度）
 */
void out_set_spray(int level);

/**
 * @brief 紧急停机：4 电机回 1ms + 水泵关闭
 */
void out_emergency(void);

#ifdef __cplusplus
}
#endif

#endif /* OUT_PWM_H */
