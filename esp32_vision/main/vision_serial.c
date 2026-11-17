/**
 * vision_serial - 串口图传实现
 */
#include <string.h>
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "driver/uart.h"
#include "vision_serial.h"
#include "vision_cam.h"

#define VS_UART        UART_NUM_0
#define VS_BAUD_IDLE   115200
#define VS_BAUD_STREAM 3000000
#define RX_BUF         4096
#define TX_BUF         8192

static bool s_streaming = false;   // 串口推流中（= 3M 波特率 + 日志静默）

static const char *k_ack_ss = "VOK SS 3000000\n";
static const char *k_ack_se = "VOK SE 115200\n";
static const char *k_err_need = "VERR need VSS first\n";

static void vs_write(const char *s, int len)
{
    uart_write_bytes(VS_UART, s, len);
}

static void vs_send_frame(uint8_t type, camera_fb_t *fb)
{
    uint8_t hdr[8] = {
        'H', 'V', type,
        (uint8_t)(fb->len), (uint8_t)(fb->len >> 8),
        (uint8_t)(fb->len >> 16), (uint8_t)(fb->len >> 24), 0
    };
    uart_write_bytes(VS_UART, hdr, 8);
    uart_write_bytes(VS_UART, (const char *)fb->buf, fb->len);
}

static void vs_enter_stream(void)
{
    if (s_streaming) return;
    vs_write(k_ack_ss, strlen(k_ack_ss));          // 115200 下回执
    vTaskDelay(pdMS_TO_TICKS(120));                // 让PC切波特率
    uart_set_baudrate(VS_UART, VS_BAUD_STREAM);
    esp_log_level_set("*", ESP_LOG_NONE);          // 静默日志防污染数据流
    s_streaming = true;
}

static void vs_exit_stream(void)
{
    if (!s_streaming) return;
    s_streaming = false;
    uart_flush_input(VS_UART);
    uart_set_baudrate(VS_UART, VS_BAUD_IDLE);
    esp_log_level_set("*", ESP_LOG_INFO);
    vs_write(k_ack_se, strlen(k_ack_se));          // 已切回115200
}

static void vs_snapshot(int res_idx)
{
    if (!s_streaming) {
        vs_write(k_err_need, strlen(k_err_need));
        return;
    }
    if (res_idx < 0 || res_idx >= 8) res_idx = 5;

    int saved = cam_get_stream_res();
    cam_set_stream_res(res_idx);
    vTaskDelay(pdMS_TO_TICKS(120));

    char msg[48];
    int ml = snprintf(msg, sizeof(msg), "SNAP begin res=%d\n", res_idx);
    vs_write(msg, ml);

    // 切分辨率后传感器PLL重启需几百毫秒，首帧可能取空，加重试
    camera_fb_t *fb = NULL;
    for (int tries = 0; tries < 10 && !fb; tries++) {
        fb = cam_capture();
        if (!fb) vTaskDelay(pdMS_TO_TICKS(150));
    }
    if (!fb) {
        ml = snprintf(msg, sizeof(msg), "SNAP null res=%d\n", res_idx);
        vs_write(msg, ml);
        cam_set_stream_res(saved);
        return;
    }
    vs_send_frame(0x04, fb);
    cam_release(fb);
    ml = snprintf(msg, sizeof(msg), "SNAP ok len=%u\n", (unsigned)fb->len);
    vs_write(msg, ml);
    cam_set_stream_res(saved);
}

static void vs_handle_line(const char *line, int len)
{
    if (len <= 0) return;
    if (!strncmp(line, "VSS", 3)) {
        vs_enter_stream();
    } else if (!strncmp(line, "VSE", 3)) {
        vs_exit_stream();
    } else if (!strncmp(line, "VS1", 3)) {
        vs_snapshot(5);    // UXGA 1600x1200（OV5640@20MHz 稳定档）
    } else if (!strncmp(line, "VS2", 3)) {
        vs_snapshot(7);    // QSXGA 5MP（实验档，可能无帧，需按RST恢复）
    }
}

static void serial_task(void *pv)
{
    char line[32];
    int llen = 0;
    uint8_t buf[128];

    while (1) {
        int n = uart_read_bytes(VS_UART, buf, sizeof(buf), pdMS_TO_TICKS(20));
        if (n > 0) {
            for (int i = 0; i < n; i++) {
                if (buf[i] == '\n' || buf[i] == '\r') {
                    vs_handle_line(line, llen);
                    llen = 0;
                } else if (llen < (int)sizeof(line) - 1) {
                    line[llen++] = (char)buf[i];
                }
            }
        }
        if (s_streaming) {
            camera_fb_t *fb = cam_capture();
            if (fb) {
                vs_send_frame(0x03, fb);
                cam_release(fb);
            } else {
                vTaskDelay(pdMS_TO_TICKS(50));
            }
        }
    }
}

esp_err_t vision_serial_start(void)
{
    uart_config_t cfg = {
        .baud_rate = VS_BAUD_IDLE,
        .data_bits = UART_DATA_8_BITS,
        .parity    = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    // 控制台占用了UART0，驱动安装后两者共存；推流期间日志已静默
    ESP_ERROR_CHECK(uart_driver_install(VS_UART, RX_BUF, TX_BUF, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(VS_UART, &cfg));
    ESP_ERROR_CHECK(uart_set_pin(VS_UART, 43, 44, -1, -1));  // UART0默认引脚

    if (xTaskCreate(serial_task, "vserial", 6144, NULL, 5, NULL) != pdPASS) {
        return ESP_FAIL;
    }
    return ESP_OK;
}
