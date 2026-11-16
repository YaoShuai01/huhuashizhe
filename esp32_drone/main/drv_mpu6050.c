/**
 * drv_mpu6050.c - MPU6050 六轴 IMU 驱动（I2C, ESP-IDF v5.3 i2c_master API）
 * 护花使者 ESP32-S3 飞控
 */
#include <string.h>
#include "driver/i2c_master.h"
#include "driver/gpio.h"
#include "esp_rom_sys.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "drv_mpu6050.h"

static const char *TAG = "MPU6050";

static i2c_master_bus_handle_t s_bus = NULL;
static i2c_master_dev_handle_t s_dev = NULL;
static bool s_valid = false;

// 标定偏移（LSB）
static int16_t s_gyro_off[3] = {0, 0, 0};
static int16_t s_accel_off[3] = {0, 0, 0};

// ==================== 内部工具 ====================

static esp_err_t mpu6050_write_reg(uint8_t reg, uint8_t val)
{
    uint8_t buf[2] = {reg, val};
    return i2c_master_transmit(s_dev, buf, sizeof(buf), pdMS_TO_TICKS(50));
}

static esp_err_t mpu6050_read_regs(uint8_t reg, uint8_t *data, size_t len)
{
    return i2c_master_transmit_receive(s_dev, &reg, 1, data, len, pdMS_TO_TICKS(50));
}

// I2C 总线恢复：热复位（EN）时 MPU6050 不断电，若复位瞬间它正作为从机把 SDA
// 拉在低电平，新主机检测到总线忙，probe 会一直超时。按 I2C 规范手动产生最多
// 9 个 SCL 时钟脉冲等待从机释放 SDA，再补发一个 STOP，使总线回到空闲态。
static void i2c_bus_recovery(void)
{
    gpio_config_t io = {
        .pin_bit_mask = (1ULL << MPU6050_SDA_GPIO) | (1ULL << MPU6050_SCL_GPIO),
        .mode = GPIO_MODE_INPUT_OUTPUT_OD,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&io);

    // 释放两条线（开漏输出高 = 高阻，靠上拉拉高）
    gpio_set_level(MPU6050_SDA_GPIO, 1);
    gpio_set_level(MPU6050_SCL_GPIO, 1);
    esp_rom_delay_us(10);

    // 最多 9 个时钟脉冲，直到 SDA 被从机释放
    for (int i = 0; i < 9 && gpio_get_level(MPU6050_SDA_GPIO) == 0; i++) {
        gpio_set_level(MPU6050_SCL_GPIO, 0);
        esp_rom_delay_us(10);
        gpio_set_level(MPU6050_SCL_GPIO, 1);
        esp_rom_delay_us(10);
    }

    // 产生 STOP：SCL 为高时 SDA 由低拉高
    gpio_set_level(MPU6050_SDA_GPIO, 0);
    esp_rom_delay_us(10);
    gpio_set_level(MPU6050_SCL_GPIO, 1);
    esp_rom_delay_us(10);
    gpio_set_level(MPU6050_SDA_GPIO, 1);
    esp_rom_delay_us(10);

    // 复位为默认 GPIO 状态，随后交由 i2c_master 重新接管
    gpio_reset_pin(MPU6050_SDA_GPIO);
    gpio_reset_pin(MPU6050_SCL_GPIO);
}

// 释放已有 I2C 资源（重复调用 init 时使用）
static void release_handles(void)
{
    if (s_dev) { i2c_master_bus_rm_device(s_dev); s_dev = NULL; }
    if (s_bus) { i2c_del_master_bus(s_bus);        s_bus = NULL; }
    s_valid = false;
}

// ==================== 对外接口 ====================

esp_err_t mpu6050_init(void)
{
    // 允许重复调用（运行时自愈）：先释放旧资源
    release_handles();

    esp_err_t err = ESP_FAIL;
    for (int attempt = 0; attempt < 6; attempt++) {
        if (attempt > 0) {
            vTaskDelay(pdMS_TO_TICKS(50));
        }
        // 每次尝试前做总线恢复（即使 SDA 没被拉低也无副作用）
        i2c_bus_recovery();

        // 1) 创建 I2C 总线（GY-521 自带 4.7k 上拉，内部上拉兜底）
        i2c_master_bus_config_t bus_cfg = {
            .i2c_port = I2C_NUM_0,
            .sda_io_num = MPU6050_SDA_GPIO,
            .scl_io_num = MPU6050_SCL_GPIO,
            .clk_source = I2C_CLK_SRC_DEFAULT,
            .glitch_ignore_cnt = 7,
            .flags.enable_internal_pullup = true,
        };
        err = i2c_new_master_bus(&bus_cfg, &s_bus);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "第 %d 次尝试: 总线创建失败 %s", attempt + 1, esp_err_to_name(err));
            s_bus = NULL;
            continue;
        }

        // 2) probe 检测设备 ACK（xfer 超时 100ms）
        err = i2c_master_probe(s_bus, MPU6050_I2C_ADDR, 100);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "第 %d 次尝试: probe 0x%02X 失败 (%s)，将总线恢复后重试",
                     attempt + 1, MPU6050_I2C_ADDR, esp_err_to_name(err));
            release_handles();
            continue;
        }

        // 3) 添加设备
        i2c_device_config_t dev_cfg = {
            .dev_addr_length = I2C_ADDR_BIT_LEN_7,
            .device_address = MPU6050_I2C_ADDR,
            .scl_speed_hz = MPU6050_I2C_CLK_HZ,
        };
        err = i2c_master_bus_add_device(s_bus, &dev_cfg, &s_dev);
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "第 %d 次尝试: 添加设备失败 %s", attempt + 1, esp_err_to_name(err));
            release_handles();
            continue;
        }

        // 4) WHO_AM_I 校验（每次最多 5 次小重试）
        uint8_t who = 0;
        err = ESP_FAIL;
        for (int i = 0; i < 5; i++) {
            who = 0;
            err = mpu6050_read_regs(MPU6050_REG_WHO_AM_I, &who, 1);
            if (err == ESP_OK && who == 0x68) break;
            ESP_LOGW(TAG, "第 %d 次尝试: WHO_AM_I 第 %d 小次失败 (%s, who=0x%02X)",
                     attempt + 1, i + 1, err == ESP_OK ? "OK" : esp_err_to_name(err), who);
            vTaskDelay(pdMS_TO_TICKS(20));
        }
        if (err != ESP_OK || who != 0x68) {
            ESP_LOGW(TAG, "第 %d 次尝试: WHO_AM_I 未通过，释放后恢复重试", attempt + 1);
            release_handles();
            continue;
        }

        // 5) 寄存器配置
        // PWR_MGMT_1: 退出休眠，时钟选 PLL(Z轴陀螺)，yaw 最稳
        mpu6050_write_reg(MPU6050_REG_PWR_MGMT_1, 0x01);
        // SMPLRT_DIV=0: DLPF 开启时陀螺输出率 = 1kHz → 1kHz 采样
        mpu6050_write_reg(MPU6050_REG_SMPLRT_DIV, 0x00);
        // CONFIG: DLPF_CFG=2 → 陀螺 98Hz / 加速度 94Hz 低通（抑制电机振动）
        mpu6050_write_reg(MPU6050_REG_CONFIG, 0x02);
        // GYRO_CONFIG: FS_SEL=1 → ±500dps（65.5 LSB/dps），比 ±250 抗振不饱和
        mpu6050_write_reg(MPU6050_REG_GYRO_CONFIG, 0x08);
        // ACCEL_CONFIG: AFS_SEL=0 → ±2g（16384 LSB/g）
        mpu6050_write_reg(MPU6050_REG_ACCEL_CONFIG, 0x00);

        s_valid = true;
        ESP_LOGI(TAG, "MPU6050 初始化成功 (第 %d 次尝试, addr=0x%02X, SDA=GPIO%d SCL=GPIO%d, %dHz)",
                 attempt + 1, MPU6050_I2C_ADDR, MPU6050_SDA_GPIO, MPU6050_SCL_GPIO,
                 MPU6050_I2C_CLK_HZ);
        ESP_LOGI(TAG, "量程: 陀螺±500dps 加速度±2g  DLPF: 陀螺98Hz 加速度94Hz");
        return ESP_OK;
    }

    ESP_LOGE(TAG, "MPU6050 初始化失败（已总线恢复重试 6 次）: %s", esp_err_to_name(err));
    return err;
}

esp_err_t mpu6050_read(int16_t accel[3], int16_t gyro[3], int16_t *temp)
{
    if (!s_valid || s_dev == NULL) {
        return ESP_ERR_INVALID_STATE;   // 未成功初始化，避免空句柄狂刷底层错误
    }
    uint8_t buf[14];
    esp_err_t err = mpu6050_read_regs(MPU6050_REG_ACCEL_XOUT, buf, sizeof(buf));
    if (err != ESP_OK) {
        return err;
    }
    // 大端序
    accel[0] = (int16_t)((buf[0]  << 8) | buf[1]);
    accel[1] = (int16_t)((buf[2]  << 8) | buf[3]);
    accel[2] = (int16_t)((buf[4]  << 8) | buf[5]);
    *temp    = (int16_t)((buf[6]  << 8) | buf[7]);
    gyro[0]  = (int16_t)((buf[8]  << 8) | buf[9]);
    gyro[1]  = (int16_t)((buf[10] << 8) | buf[11]);
    gyro[2]  = (int16_t)((buf[12] << 8) | buf[13]);

    // 去偏移
    accel[0] -= s_accel_off[0];
    accel[1] -= s_accel_off[1];
    accel[2] -= s_accel_off[2];
    gyro[0]  -= s_gyro_off[0];
    gyro[1]  -= s_gyro_off[1];
    gyro[2]  -= s_gyro_off[2];
    return ESP_OK;
}

esp_err_t mpu6050_calibrate(int n)
{
    if (!s_valid || n <= 0) return ESP_ERR_INVALID_STATE;

    int64_t g_sum[3] = {0, 0, 0};
    int64_t a_sum[3] = {0, 0, 0};
    int ok = 0;

    for (int i = 0; i < n; i++) {
        int16_t accel[3], gyro[3], temp;
        if (mpu6050_read(accel, gyro, &temp) == ESP_OK) {
            for (int j = 0; j < 3; j++) {
                g_sum[j] += gyro[j] + s_gyro_off[j];   // 读函数已去偏移，这里加回原始值
                a_sum[j] += accel[j] + s_accel_off[j];
            }
            ok++;
        }
        vTaskDelay(pdMS_TO_TICKS(1));
    }

    if (ok == 0) {
        ESP_LOGE(TAG, "标定失败：未读到任何有效数据");
        return ESP_ERR_TIMEOUT;
    }

    for (int j = 0; j < 3; j++) {
        s_gyro_off[j] = (int16_t)(g_sum[j] / ok);
        s_accel_off[j] = (int16_t)(a_sum[j] / ok);
    }
    // 加速度计零偏：扣除重力分量（静止时 Z 轴应 ≈ +1g = 16384 LSB，朝上）
    s_accel_off[2] -= 16384;

    ESP_LOGI(TAG, "标定完成 (n=%d)：陀螺零偏 [%d %d %d] LSB，加速度零偏 [%d %d %d] LSB",
             ok, s_gyro_off[0], s_gyro_off[1], s_gyro_off[2],
             s_accel_off[0], s_accel_off[1], s_accel_off[2]);
    return ESP_OK;
}

void mpu6050_get_offsets(int16_t g_off[3], int16_t a_off[3])
{
    memcpy(g_off, s_gyro_off, sizeof(s_gyro_off));
    memcpy(a_off, s_accel_off, sizeof(s_accel_off));
}

bool mpu6050_is_valid(void)
{
    return s_valid;
}