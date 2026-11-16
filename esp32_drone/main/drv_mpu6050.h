/**
 * drv_mpu6050.h - MPU6050 六轴 IMU 驱动（I2C, ESP-IDF v5.3 i2c_master API）
 * 护花使者 ESP32-S3 飞控
 * 接线：VCC→3V3, GND→GND, SDA→GPIO41, SCL→GPIO42
 */
#ifndef DRV_MPU6050_H
#define DRV_MPU6050_H

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// ==================== 硬件配置 ====================
#define MPU6050_I2C_ADDR     0x68    // AD0 低电平
#define MPU6050_SDA_GPIO     41
#define MPU6050_SCL_GPIO     42
#define MPU6050_I2C_CLK_HZ   100000

// 寄存器地址
#define MPU6050_REG_SMPLRT_DIV  0x19
#define MPU6050_REG_CONFIG      0x1A
#define MPU6050_REG_GYRO_CONFIG 0x1B
#define MPU6050_REG_ACCEL_CONFIG 0x1C
#define MPU6050_REG_ACCEL_XOUT  0x3B   // 突发读起点（ACCEL 6B + TEMP 2B + GYRO 6B = 14B）
#define MPU6050_REG_PWR_MGMT_1  0x6B
#define MPU6050_REG_WHO_AM_I    0x75

// 量程换算
#define MPU6050_GYRO_SCALE      (1.0f / 65.5f)   // ±500dps → dps/LSB
#define MPU6050_ACCEL_SCALE     (1.0f / 16384.0f) // ±2g → g/LSB
#define DEG_TO_RAD              (0.017453292519943295f)

/**
 * @brief 初始化 I2C 总线 + MPU6050 寄存器配置 + WHO_AM_I 校验
 * @return ESP_OK 成功；ESP_ERR_NOT_FOUND 未检测到芯片；其他为 I2C 错误
 */
esp_err_t mpu6050_init(void);

/**
 * @brief 突发读取 14 字节（ACCEL+TEMP+GYRO）
 * @param accel[3] 加速度原始值（LSB）
 * @param gyro[3]  陀螺原始值（LSB）
 * @param temp    温度原始值（LSB）
 * @return ESP_OK 成功
 */
esp_err_t mpu6050_read(int16_t accel[3], int16_t gyro[3], int16_t *temp);

/**
 * @brief 静止标定：采集 n 帧，计算陀螺零偏与加速度计零偏
 */
esp_err_t mpu6050_calibrate(int n);

/**
 * @brief 获取标定后的偏移量
 * @param g_off[3] 陀螺偏移（LSB）
 * @param a_off[3] 加速度偏移（LSB）
 */
void mpu6050_get_offsets(int16_t g_off[3], int16_t a_off[3]);

/**
 * @brief 判断传感器是否有效（WHO_AM_I 校验通过且初始化成功）
 */
bool mpu6050_is_valid(void);

#ifdef __cplusplus
}
#endif

#endif /* DRV_MPU6050_H */
