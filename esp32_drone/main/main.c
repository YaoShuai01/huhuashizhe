/**
 * 护花使者 - 无人机验证平台 (ESP32-S3) - PX4 工程思维重构版
 *
 * 模块化分层（对应 PX4 各模块）：
 *   drv_mpu6050   - 传感器驱动     (对应 driver)
 *   est_attitude  - 姿态估计 Mahony (对应 attitude_estimator_q)
 *   ctl_controller- 串级姿态控制    (对应 mc_att_control + mc_rate_control)
 *   mix_mixer     - 归一化混控      (对应 mixer)
 *   out_pwm       - 执行机构输出    (对应 actuator_outputs)
 *   rc_udp        - 遥控输入        (对应 rc_update)
 *   cmd_commander - 飞行指挥/状态机 (对应 commander)
 *   prm_params    - 参数表          (对应 params)
 *
 * 任务调度（固定频率，PX4 风格）：
 *   imu_task       1kHz  读 MPU6050 → imu_data → 姿态估计
 *   ctl_task       250Hz 姿态 → 串级控制 → 混控 → PWM 输出
 *   commander_task 100Hz 遥控 → 状态机 → 控制设定值
 *   udp_server     50Hz  遥控协议解析（网络任务）
 *   heartbeat_task 2Hz   心跳超时监测
 *
 * 硬件：
 *   GPIO1=前右, GPIO4=前左, GPIO21=后右, GPIO12=后左（电调信号 50Hz/14bit）
 *   GPIO18=喷洒水泵（MOS 管，5kHz/8bit）
 *   MPU6050: SDA→GPIO8, SCL→GPIO9（400kHz I2C）
 */

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_mac.h"
#include "nvs_flash.h"
#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "lwip/netdb.h"

#include "driver/gpio.h"

#include "drone_types.h"
#include "prm_params.h"
#include "drv_mpu6050.h"
#include "est_attitude.h"
#include "ctl_controller.h"
#include "out_pwm.h"
#include "rc_udp.h"
#include "cmd_commander.h"

static const char *TAG = "DRONE";

// ==================== WiFi AP 配置 ====================
#define WIFI_SSID      "HuHuaShiZhe-Drone"
#define WIFI_PASSWORD  ""
// 信道6 + HT40：副信道10，中心频率对应信道8，覆盖4~12，是2.4G做40MHz的常用组合。
// 原来信道1做HT40会挤在频段最边缘，抗干扰差。
#define WIFI_CHANNEL   6
#define WIFI_MAX_CONN 2   // 手机 + 视觉板

// ==================== WiFi 事件处理 ====================
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_AP_STACONNECTED) {
        wifi_event_ap_staconnected_t *event = (wifi_event_ap_staconnected_t *)event_data;
        ESP_LOGI(TAG, "手机已连接: MAC=" MACSTR, MAC2STR(event->mac));
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_AP_STADISCONNECTED) {
        wifi_event_ap_stadisconnected_t *ev =
            (wifi_event_ap_stadisconnected_t *)event_data;
        // reason: 8=手机主动离开(常因"无互联网"被手机系统切走) 15=四次握手超时
        //         19=关联过期 200/201=信标超时 等
        ESP_LOGW(TAG, "手机已断开 (reason=%u)，通知指挥层紧急停机",
                 (unsigned)ev->reason);
        cmd_notify_wifi_disconnected();
    }
}

static void wifi_init_ap(void)
{
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_ap();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT,
        ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL));

    wifi_config_t wifi_config = {
        .ap = {
            .ssid = WIFI_SSID,
            .ssid_len = strlen(WIFI_SSID),
            .channel = WIFI_CHANNEL,
            .password = WIFI_PASSWORD,
            .max_connection = WIFI_MAX_CONN,
            .authmode = WIFI_AUTH_OPEN,
        },
    };

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());

    // ★ 40MHz带宽(HT40)：手机与视觉板都在本AP下，图传数据由AP转发，
    //   HT20时这条转发链路吞吐被限制在一半（约5-6Mbps），
    //   720p以上码流必然丢包卡顿。HT40可让转发吞吐翻倍。
    //   注意必须在 esp_wifi_start() 之后调用。
    esp_err_t bw_err = esp_wifi_set_bandwidth(WIFI_IF_AP, WIFI_BW_HT40);
    if (bw_err != ESP_OK) {
        ESP_LOGW(TAG, "HT40设置失败(0x%x)，回退HT20", bw_err);
    } else {
        ESP_LOGI(TAG, "WiFi带宽已设为HT40(40MHz)");
    }

    // AP 侧不活跃超时缩短到 10s（默认 300s）：手机异常掉线未发 deauth 时，
    // 旧关联槽位 10 秒后即被回收，避免唯一槽位被僵尸设备长期占用导致手机再也连不上。
    esp_wifi_set_inactive_time(WIFI_IF_AP, 10);

    ESP_LOGI(TAG, "WiFi AP 已启动: SSID=%s, 信道=%d, 最大连接=%d",
             WIFI_SSID, WIFI_CHANNEL, WIFI_MAX_CONN);
}

// ==================== imu_task: 1kHz 采样 + 姿态估计 ====================
static void imu_task(void *arg)
{
    const prm_param_t *p = prm_get();
    int64_t period_us = 1000000LL / (int64_t)p->imu_hz;
    TickType_t period_tick = pdMS_TO_TICKS(1000 / p->imu_hz);
    if (period_tick == 0) period_tick = 1;   // 1000Hz@1000tick = 1 拍
    TickType_t last_wake = xTaskGetTickCount();
    int fail_cnt = 0;
    bool imu_ok = true;

    // 运行时自愈：开机 init 成功则 app_main 已标定；否则首次恢复成功后补标定
    bool calibrated_once = mpu6050_is_valid();
    int64_t last_retry_us = 0;

    ESP_LOGI(TAG, "imu_task 启动 (%uHz, 周期 %lldus / %u 拍)", (unsigned)p->imu_hz,
             (long long)period_us, (unsigned)period_tick);

    while (1) {
        int16_t accel[3], gyro[3], temp;
        imu_data_t imu;
        memset(&imu, 0, sizeof(imu));

        esp_err_t rd = mpu6050_read(accel, gyro, &temp);
        if (rd == ESP_OK) {
            fail_cnt = 0;
            // LSB → 物理量（读函数已扣除标定偏移）
            imu.ax = (float)accel[0] * MPU6050_ACCEL_SCALE;
            imu.ay = (float)accel[1] * MPU6050_ACCEL_SCALE;
            imu.az = (float)accel[2] * MPU6050_ACCEL_SCALE;
            imu.gx = (float)gyro[0] * MPU6050_GYRO_SCALE * DEG_TO_RAD;
            imu.gy = (float)gyro[1] * MPU6050_GYRO_SCALE * DEG_TO_RAD;
            imu.gz = (float)gyro[2] * MPU6050_GYRO_SCALE * DEG_TO_RAD;
            imu.valid = true;
        } else {
            fail_cnt++;
            imu.valid = false;

            // 运行时自愈：开机即失效（未初始化），或初始化后总线卡死（连续 200 帧失败），
            // 每秒最多尝试一次：总线恢复(9时钟+STOP) + 重新初始化 + 必要时补标定
            int64_t now_try = esp_timer_get_time();
            bool init_failed = !mpu6050_is_valid();
            bool bus_hung    = mpu6050_is_valid() && fail_cnt >= 200;
            if ((init_failed || bus_hung) && (now_try - last_retry_us) >= 1000000) {
                last_retry_us = now_try;
                ESP_LOGW(TAG, "IMU 连续失败 %d 帧，执行总线恢复+重初始化", fail_cnt);
                if (mpu6050_init() == ESP_OK) {
                    if (!calibrated_once) {
                        mpu6050_calibrate(500);
                        calibrated_once = true;
                    }
                    fail_cnt = 0;
                    imu_ok = true;
                    cmd_notify_imu_valid();
                    ESP_LOGI(TAG, "IMU 运行时恢复成功");
                }
            }
        }
        imu.timestamp_us = esp_timer_get_time();

        // 失效/恢复 通知指挥层（连续失败帧数达到阈值才判定失效）
        if (imu.valid) {
            if (!imu_ok && fail_cnt == 0) {
                imu_ok = true;
                cmd_notify_imu_valid();
            }
        } else if (imu_ok && fail_cnt >= (int)p->imu_fail_frames) {
            imu_ok = false;
            cmd_notify_imu_invalid();
        }

        // 姿态估计（内部 1kHz 融合，250Hz 发布）
        est_attitude_update(&imu);

        // 固定 1kHz 节拍（vTaskDelayUntil 保证绝对周期，且必定阻塞让出 CPU）
        vTaskDelayUntil(&last_wake, period_tick);
    }
}

// ==================== ctl_task: 250Hz 姿态控制 ====================
static void ctl_task(void *arg)
{
    const prm_param_t *p = prm_get();
    TickType_t period = pdMS_TO_TICKS(1000 / (uint32_t)p->ctl_hz);
    TickType_t last_wake = xTaskGetTickCount();

    ESP_LOGI(TAG, "ctl_task 启动 (%uHz)", (unsigned)p->ctl_hz);

    while (1) {
        attitude_data_t att;
        est_attitude_get(&att);
        ctl_step(&att);
        vTaskDelayUntil(&last_wake, period);
    }
}

// ==================== commander_task: 100Hz 状态机 ====================
static void commander_task(void *arg)
{
    ESP_LOGI(TAG, "commander_task 启动 (100Hz)");

    while (1) {
        cmd_run();
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}

// ==================== heartbeat_task: 2Hz 心跳超时监测 ====================
static void heartbeat_task(void *arg)
{
    const prm_param_t *p = prm_get();

    ESP_LOGI(TAG, "heartbeat_task 启动 (2Hz, 超时 %ums)", (unsigned)p->cmd_timeout_ms);

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(500));

        rc_input_t rc;
        rc_get_input(&rc);
        uint32_t now = (uint32_t)(esp_timer_get_time() / 1000);
        uint32_t since = now - rc.last_rx_ms;
        if (since > p->cmd_timeout_ms) {
            cmd_notify_heartbeat_timeout();
        }
    }
}

// ==================== 主函数 ====================
void app_main(void)
{
    // 1) NVS（WiFi 依赖）
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // 2) 执行机构输出（电调 50Hz + 水泵 5kHz），out_init 内部立即输出 1ms 最小油门，
    //    电调收到有效信号后完成自检（蜂鸣 + 灯）
    ESP_ERROR_CHECK(out_init());

    // 3) MPU6050 初始化 + 静止标定（失败不阻断启动，imu_task 会上报失效并锁定解锁）
    esp_err_t imu_ret = mpu6050_init();
    if (imu_ret == ESP_OK) {
        mpu6050_calibrate(1000);
    } else {
        ESP_LOGE(TAG, "MPU6050 初始化失败(%s)，飞控将保持锁定，请检查陀螺仪接线", esp_err_to_name(imu_ret));
    }

    // 4) 姿态估计 / 控制器 / 指挥层
    est_attitude_init();
    ctl_init();
    cmd_init();

    // 5) WiFi AP + UDP 遥控
    wifi_init_ap();
    rc_init();
    rc_udp_task_start();

    // 6) 固定频率任务（PX4 风格）
    xTaskCreate(imu_task,       "imu",       4096, NULL, 5, NULL);
    xTaskCreate(ctl_task,       "ctl",       4096, NULL, 4, NULL);
    xTaskCreate(commander_task, "commander", 4096, NULL, 3, NULL);
    xTaskCreate(heartbeat_task, "heartbeat", 2048, NULL, 2, NULL);

    ESP_LOGI(TAG, "护花使者飞控已就绪 (IMU=%s)", mpu6050_is_valid() ? "有效" : "失效-锁定");
    ESP_LOGI(TAG, "电调引脚: FR=GPIO1, FL=GPIO4, BR=GPIO21, BL=GPIO12 | 水泵=GPIO18");
    ESP_LOGI(TAG, "陀螺仪: SDA=GPIO%d SCL=GPIO%d", 8, 9);
    ESP_LOGI(TAG, "警告: 解锁前务必确认螺旋桨已拆下");
    ESP_LOGI(TAG, "请用手机连接WiFi: %s", WIFI_SSID);
}
