/**
 * ESP32-P4 + OV5647 H.264 实时推流
 *
 * OV5647 MIPI-CSI → ISP(RGB565) → 硬件 H.264 → 原生 USB-Serial-JTAG → 电脑
 * 协议：'H''V' + type(0x02) + len32(LE) + H.264 Annex-B 数据
 */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <sys/mman.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs_flash.h"
#include "driver/usb_serial_jtag.h"
#include "driver/spi_master.h"
#include "linux/videodev2.h"

#include "example_video_common.h"
#include "esp_h264_enc_single_hw.h"
#include "esp_h264_alloc.h"

static const char *TAG = "P4H264";

#define CAPTURE_BUFFERS 2
#define TARGET_FPS      15
#define TARGET_BITRATE  (5 * 1000 * 1000)
#define SEND_CHUNK      4096

/* P4 → 飞控 SPI（4 根线） */
#define PIN_SPI_SCLK    20
#define PIN_SPI_MOSI    21
#define PIN_SPI_CS      22
#define SPI_CHUNK       2048

static void fourcc_str(uint32_t f, char out[5])
{
    out[0] = (char)(f & 0xff);
    out[1] = (char)((f >> 8) & 0xff);
    out[2] = (char)((f >> 16) & 0xff);
    out[3] = (char)((f >> 24) & 0xff);
    out[4] = '\0';
}

static spi_device_handle_t s_spi = NULL;
static uint8_t s_spi_buf[SPI_CHUNK] __attribute__((aligned(4)));

static bool spi_bridge_init(void)
{
    spi_bus_config_t buscfg = {
        .mosi_io_num = PIN_SPI_MOSI,
        .miso_io_num = -1,
        .sclk_io_num = PIN_SPI_SCLK,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = SPI_CHUNK,
    };
    if (spi_bus_initialize(SPI2_HOST, &buscfg, SPI_DMA_CH_AUTO) != ESP_OK) {
        ESP_LOGW(TAG, "SPI 总线初始化失败");
        return false;
    }
    spi_device_interface_config_t devcfg = {
        .clock_speed_hz = 20 * 1000 * 1000,
        .mode = 0,
        .spics_io_num = PIN_SPI_CS,
        .queue_size = 1,
    };
    if (spi_bus_add_device(SPI2_HOST, &devcfg, &s_spi) != ESP_OK) {
        ESP_LOGW(TAG, "SPI 设备添加失败");
        return false;
    }
    ESP_LOGI(TAG, "SPI 桥就绪: SCLK=%d MOSI=%d CS=%d 20MHz",
             PIN_SPI_SCLK, PIN_SPI_MOSI, PIN_SPI_CS);
    return true;
}

static bool spi_bridge_send(const uint8_t *buf, uint32_t len)
{
    if (!s_spi) return false;
    uint32_t off = 0;
    while (off < len) {
        uint32_t n = len - off;
        if (n > SPI_CHUNK) n = SPI_CHUNK;
        memcpy(s_spi_buf, buf + off, n);
        spi_transaction_t t = { 0 };
        t.length = n * 8;
        t.tx_buffer = s_spi_buf;
        if (spi_device_transmit(s_spi, &t) != ESP_OK) return false;
        off += n;
    }
    return true;
}

static bool send_nal(const uint8_t *buf, uint32_t len)
{
    uint8_t hdr[8] = {
        'H', 'V', 0x02,
        (uint8_t)(len), (uint8_t)(len >> 8),
        (uint8_t)(len >> 16), (uint8_t)(len >> 24), 0
    };
    if (usb_serial_jtag_write_bytes(hdr, sizeof(hdr), pdMS_TO_TICKS(1000)) != sizeof(hdr)) {
        return false;
    }
    uint32_t sent = 0;
    while (sent < len) {
        uint32_t chunk = len - sent;
        if (chunk > SEND_CHUNK) chunk = SEND_CHUNK;
        int n = usb_serial_jtag_write_bytes(buf + sent, chunk, pdMS_TO_TICKS(2000));
        if (n <= 0) return false;
        sent += n;
    }
    return true;
}

static bool spi_send_frame(const uint8_t *buf, uint32_t len)
{
    uint8_t hdr[8] = {
        'H', 'V', 0x02,
        (uint8_t)(len), (uint8_t)(len >> 8),
        (uint8_t)(len >> 16), (uint8_t)(len >> 24), 0
    };
    return spi_bridge_send(hdr, sizeof(hdr)) && spi_bridge_send(buf, len);
}

void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    }

    ESP_LOGI(TAG, "=== ESP32-P4 OV5647 H.264 推流 ===");
    ESP_ERROR_CHECK(example_video_init());

    int fd = open(EXAMPLE_CAM_DEV_PATH, O_RDWR);
    if (fd < 0) {
        ESP_LOGE(TAG, "打开 %s 失败 errno=%d", EXAMPLE_CAM_DEV_PATH, errno);
        return;
    }

    struct v4l2_format fmt;
    memset(&fmt, 0, sizeof(fmt));
    fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (ioctl(fd, VIDIOC_G_FMT, &fmt) != 0) {
        ESP_LOGE(TAG, "VIDIOC_G_FMT 失败 errno=%d", errno);
        close(fd);
        return;
    }
    char cc[5];
    fourcc_str(fmt.fmt.pix.pixelformat, cc);
    const uint32_t width = fmt.fmt.pix.width;
    const uint32_t height = fmt.fmt.pix.height;
    ESP_LOGI(TAG, "采集格式: %ux%u %s", width, height, cc);

    /* 硬件 H.264 编码器：直接吃 RGB565 */
    esp_h264_enc_cfg_hw_t cfg = {
        .pic_type = ESP_H264_RAW_FMT_RGB565_LE,
        .gop      = 15,
        .fps      = TARGET_FPS,
        .res      = { .width = width, .height = height },
        .rc       = { .bitrate = TARGET_BITRATE, .qp_min = 18, .qp_max = 30 },
    };
    esp_h264_enc_handle_t enc = NULL;
    ESP_ERROR_CHECK(esp_h264_enc_hw_new(&cfg, &enc) == ESP_H264_ERR_OK ? ESP_OK : ESP_FAIL);
    ESP_ERROR_CHECK(esp_h264_enc_open(enc) == ESP_H264_ERR_OK ? ESP_OK : ESP_FAIL);
    ESP_LOGI(TAG, "H.264 编码器就绪: %ux%u %dfps %dbps", width, height, TARGET_FPS, TARGET_BITRATE);

    uint32_t out_cap = width * height * 2;
    uint8_t *out_buf = esp_h264_aligned_calloc(16, 1, out_cap, &out_cap, ESP_H264_MEM_SPIRAM);
    if (!out_buf) {
        ESP_LOGE(TAG, "H.264 输出缓冲分配失败");
        return;
    }

    usb_serial_jtag_driver_config_t usb_cfg = {
        .tx_buffer_size = 32768,
        .rx_buffer_size = 256,
    };
    if (usb_serial_jtag_driver_install(&usb_cfg) != ESP_OK) {
        ESP_LOGE(TAG, "USB-Serial-JTAG 驱动安装失败");
        return;
    }

    const bool spi_ok = spi_bridge_init();

    struct v4l2_requestbuffers req;
    memset(&req, 0, sizeof(req));
    req.count = CAPTURE_BUFFERS;
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_MMAP;
    if (ioctl(fd, VIDIOC_REQBUFS, &req) < 0) {
        ESP_LOGE(TAG, "REQBUFS 失败 errno=%d", errno);
        return;
    }

    void *buffers[CAPTURE_BUFFERS] = { 0 };
    for (int i = 0; i < CAPTURE_BUFFERS; i++) {
        struct v4l2_buffer buf;
        memset(&buf, 0, sizeof(buf));
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        buf.index = i;
        if (ioctl(fd, VIDIOC_QUERYBUF, &buf) < 0) {
            ESP_LOGE(TAG, "QUERYBUF %d 失败", i);
            return;
        }
        buffers[i] = mmap(NULL, buf.length, PROT_READ | PROT_WRITE,
                          MAP_SHARED, fd, buf.m.offset);
        if (buffers[i] == MAP_FAILED) {
            ESP_LOGE(TAG, "mmap %d 失败", i);
            return;
        }
        ioctl(fd, VIDIOC_QBUF, &buf);
    }

    int type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (ioctl(fd, VIDIOC_STREAMON, &type) < 0) {
        ESP_LOGE(TAG, "STREAMON 失败 errno=%d", errno);
        return;
    }

    if (!spi_ok) {
        ESP_LOGI(TAG, "等待电脑打开原生 USB 口（COM7）...");
        while (!usb_serial_jtag_is_connected()) {
            vTaskDelay(pdMS_TO_TICKS(500));
        }
    }
    ESP_LOGI(TAG, "开始 H.264 推流（USB=%d SPI=%d）",
             (int)usb_serial_jtag_is_connected(), (int)spi_ok);

    int64_t stat_t0 = esp_timer_get_time();
    int frames = 0;
    uint32_t bytes = 0;
    int errors = 0;

    while (1) {
        struct v4l2_buffer buf;
        memset(&buf, 0, sizeof(buf));
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        if (ioctl(fd, VIDIOC_DQBUF, &buf) < 0) {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        esp_h264_enc_in_frame_t in = {
            .raw_data = { .buffer = buffers[buf.index], .len = buf.bytesused },
            .pts = (uint32_t)(esp_timer_get_time() / 1000),
        };
        esp_h264_enc_out_frame_t out = {
            .raw_data = { .buffer = out_buf, .len = out_cap },
        };

        esp_h264_err_t er = esp_h264_enc_process(enc, &in, &out);
        if (er == ESP_H264_ERR_OK && out.length > 0) {
            bool usb_ok = usb_serial_jtag_is_connected() && send_nal(out_buf, out.length);
            bool spi_frame_ok = spi_ok && spi_send_frame(out_buf, out.length);
            if (usb_ok || spi_frame_ok) {
                frames++;
                bytes += out.length;
            } else {
                errors++;
                vTaskDelay(pdMS_TO_TICKS(10));
            }
        } else {
            errors++;
        }

        ioctl(fd, VIDIOC_QBUF, &buf);

        int64_t now = esp_timer_get_time();
        if (now - stat_t0 >= 3000000) {
            double sec = (now - stat_t0) / 1000000.0;
            ESP_LOGI(TAG, "H.264 %.1f fps, %.2f Mbps, 最近 %u 字节, 错误 %d",
                     frames / sec, bytes * 8 / sec / 1e6,
                     (unsigned)out.length, errors);
            frames = 0;
            bytes = 0;
            errors = 0;
            stat_t0 = now;
        }
    }
}
