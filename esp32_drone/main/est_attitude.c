/**
 * est_attitude.c - Mahony 姿态解算（互补滤波）
 * 护花使者 ESP32-S3 飞控
 *
 * 原理：陀螺仪积分提供短期姿态，加速度计(重力向量)提供长期修正。
 * 用四元数表示姿态，融合后输出欧拉角与体轴角速度。
 */
#include <math.h>
#include <string.h>
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "est_attitude.h"
#include "prm_params.h"

static const char *TAG = "EST";

// 四元数 (w,x,y,z)
static float s_q0 = 1.0f, s_q1 = 0.0f, s_q2 = 0.0f, s_q3 = 0.0f;

// 姿态发布数据 + 自旋锁（imu_task 与 ctl_task 同核，临界区防抢占）
static attitude_data_t s_att;
static portMUX_TYPE s_lock = portMUX_INITIALIZER_UNLOCKED;

// 发布节拍（imu_hz / ctl_hz 帧发布一次）
static uint32_t s_pub_div = 4;      // 1000/250
static uint32_t s_pub_cnt = 0;

void est_attitude_init(void)
{
    const prm_param_t *p = prm_get();
    s_pub_div = p->imu_hz / p->ctl_hz;
    if (s_pub_div < 1) s_pub_div = 1;
    s_pub_cnt = 0;
    est_attitude_reset();
    ESP_LOGI(TAG, "姿态解算初始化 (Mahony, beta=%.2f, 发布率=%uHz)",
             p->mahony_beta, (unsigned)p->ctl_hz);
}

void est_attitude_reset(void)
{
    portENTER_CRITICAL(&s_lock);
    s_q0 = 1.0f; s_q1 = 0.0f; s_q2 = 0.0f; s_q3 = 0.0f;
    memset(&s_att, 0, sizeof(s_att));
    portEXIT_CRITICAL(&s_lock);
}

void est_attitude_update(const imu_data_t *imu)
{
    const prm_param_t *p = prm_get();
    float dt = 1.0f / (float)p->imu_hz;

    if (!imu->valid) {
        return;   // 无效帧不更新
    }

    // 加速度计归一化（重力向量方向）
    float norm = sqrtf(imu->ax * imu->ax + imu->ay * imu->ay + imu->az * imu->az);
    if (norm < 1e-6f) {
        return;
    }
    float axn = imu->ax / norm;
    float ayn = imu->ay / norm;
    float azn = imu->az / norm;

    // 由四元数预测重力向量 R(q)ᵀ·(0,0,1)
    float vx = 2.0f * (s_q1 * s_q3 - s_q0 * s_q2);
    float vy = 2.0f * (s_q0 * s_q1 + s_q2 * s_q3);
    float vz = s_q0 * s_q0 - s_q1 * s_q1 - s_q2 * s_q2 + s_q3 * s_q3;

    // 误差 = 加速度计测量 × 预测（叉积）
    float ex = ayn * vz - azn * vy;
    float ey = azn * vx - axn * vz;
    float ez = axn * vy - ayn * vx;

    // 陀螺仪修正
    float gx = imu->gx + p->mahony_beta * ex;
    float gy = imu->gy + p->mahony_beta * ey;
    float gz = imu->gz + p->mahony_beta * ez;

    // 四元数积分 q̇ = 0.5·q ⊗ (0, ω)
    float half = 0.5f * dt;
    float nq0 = s_q0 + half * (-s_q1 * gx - s_q2 * gy - s_q3 * gz);
    float nq1 = s_q1 + half * ( s_q0 * gx + s_q2 * gz - s_q3 * gy);
    float nq2 = s_q2 + half * ( s_q0 * gy - s_q1 * gz + s_q3 * gx);
    float nq3 = s_q3 + half * ( s_q0 * gz + s_q1 * gy - s_q2 * gx);

    // 归一化
    norm = sqrtf(nq0 * nq0 + nq1 * nq1 + nq2 * nq2 + nq3 * nq3);
    if (norm < 1e-10f) return;
    s_q0 = nq0 / norm;
    s_q1 = nq1 / norm;
    s_q2 = nq2 / norm;
    s_q3 = nq3 / norm;

    // 按发布节拍更新姿态（250Hz）
    if (++s_pub_cnt >= s_pub_div) {
        s_pub_cnt = 0;

        // 欧拉角（限倾角 25° 内，atan2 形式对小角度同样适用）
        float roll  = atan2f(2.0f * (s_q0 * s_q1 + s_q2 * s_q3),
                             1.0f - 2.0f * (s_q1 * s_q1 + s_q2 * s_q2));
        float pitch = asinf(2.0f * (s_q0 * s_q2 - s_q3 * s_q1));
        float yaw   = atan2f(2.0f * (s_q0 * s_q3 + s_q1 * s_q2),
                             1.0f - 2.0f * (s_q2 * s_q2 + s_q3 * s_q3));

        portENTER_CRITICAL(&s_lock);
        s_att.roll = roll;
        s_att.pitch = pitch;
        s_att.yaw = yaw;
        s_att.roll_rate = gx;      // 体轴角速度（修正后）
        s_att.pitch_rate = gy;
        s_att.yaw_rate = gz;
        s_att.valid = true;
        s_att.timestamp_us = imu->timestamp_us;
        portEXIT_CRITICAL(&s_lock);
    }
}

void est_attitude_get(attitude_data_t *out)
{
    portENTER_CRITICAL(&s_lock);
    memcpy(out, &s_att, sizeof(s_att));
    portEXIT_CRITICAL(&s_lock);
}
