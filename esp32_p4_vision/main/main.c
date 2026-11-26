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
#include "driver/ppa.h"
#include "esp_cache.h"
#include "linux/videodev2.h"

#include "example_video_common.h"
#include "esp_h264_enc_single_hw.h"
#include "esp_h264_alloc.h"

static const char *TAG = "P4H264";

#define CAPTURE_BUFFERS 2
#define TARGET_FPS      20
// OV5647 1280x960 binning 模式经 V4L2/ISP 链路实测出帧约 24fps（标称 45fps 档被驱动限速）
#define SENSOR_FPS      24
// 飞控→手机下行实测上限 ~2.2Mbps（~195包/秒）。1.6Mbps 均值 + 1.4 倍 IDR
// 峰值 ≈ 2.24Mbps，恰好贴住上限；IDR 突发由飞控 40 段发送队列 + beacon50ms 吸收
#define TARGET_BITRATE  (1600 * 1000)
#define SEND_CHUNK      4096

/* 输出分辨率：OV5647 原生没有 720p，用 1280x960（2x2 binning，全视场）经 PPA 硬件缩放到 800x600 再编码。
 * 为什么不硬上 720p：1.3Mbps 摊到 1280x720 只有 0.09 bit/像素，H.264 会压出明显块状失真；
 * 800x600 在 1.5Mbps 下有 0.21 bit/像素，明显更干净。这是 2.2Mbps 下行下的最优解 */
#define OUT_WIDTH       800
#define OUT_HEIGHT      600
#define SRC_WIDTH       1280
#define SRC_HEIGHT      960
// PPA 缩放精度 1/16；800/1280 = 10/16 = 0.625，正好整除，不裁切、不丢视场
#define PPA_SCALE       (10.0f / 16.0f)
#define PPA_CROP_W      ((uint32_t)(OUT_WIDTH / PPA_SCALE) & ~1u)   /* 1280 */
#define PPA_CROP_H      ((uint32_t)(OUT_HEIGHT / PPA_SCALE) & ~1u)  /* 960 */
#define PPA_OFF_X       (((SRC_WIDTH - PPA_CROP_W) / 2) & ~1u)
#define PPA_OFF_Y       (((SRC_HEIGHT - PPA_CROP_H) / 2) & ~1u)

/* P4 → 飞控 SPI（4 根线） */
#define PIN_SPI_SCLK    20
#define PIN_SPI_MOSI    21
#define PIN_SPI_CS      22
#define SPI_CHUNK       2048

static void fourcc_str(uint32_t f, char out[5]) {
    out[0] = (char)(f & 0xff);
    out[1] = (char)((f >> 8) & 0xff);
    out[2] = (char)((f >> 16) & 0xff);
    out[3] = (char)((f >> 24) & 0xff);
    out[4] = '\0';
}

/* 诊断：把编码输入的一帧抽样成 100x75，用十六进制走日志通道输出，PC 端还原成图片，
 * 用来确认 ISP/PPA 出来的画面本身有没有问题（默认关闭） */
#define DUMP_FRAME_ENABLE 0
#if DUMP_FRAME_ENABLE
#define DUMP_STEP 8
static void dump_frame(const uint8_t *buf, int w, int h)
{
    const int ow = w / DUMP_STEP;
    const int oh = h / DUMP_STEP;
    ESP_LOGW(TAG, "@@HEX %d %d@@", ow, oh);
    for (int y = 0; y < oh; y++) {
        const uint16_t *src = (const uint16_t *)buf + (size_t)(y * DUMP_STEP) * w;
        char line[81];
        int n = 0;
        for (int x = 0; x < ow; x++) {
            n += snprintf(line + n, sizeof(line) - n, "%04x", src[x * DUMP_STEP]);
            if (n >= 64) {
                line[n] = '\0';
                ESP_LOGW(TAG, "%s", line);
                n = 0;
            }
        }
        if (n > 0) {
            line[n] = '\0';
            ESP_LOGW(TAG, "%s", line);
        }
    }
    ESP_LOGW(TAG, "@@HEXEND@@");
}
#endif

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
        // 20MHz 在长杜邦线上容易误码；装机后有电机/电调干扰，降到 8MHz 换取抗扰余量
        // （视频峰值 2.24Mbps，8MHz SPI 容量 8Mbps，余量充足）
        .clock_speed_hz = 8 * 1000 * 1000,
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

    // 驱动默认出 1280x960（binning，全视场、低照度好），PPA 再缩到 800x600
    fmt.fmt.pix.width = SRC_WIDTH;
    fmt.fmt.pix.height = SRC_HEIGHT;
    if (ioctl(fd, VIDIOC_S_FMT, &fmt) != 0) {
        ESP_LOGW(TAG, "S_FMT %dx%d 失败 errno=%d，沿用默认分辨率", SRC_WIDTH, SRC_HEIGHT, errno);
        memset(&fmt, 0, sizeof(fmt));
        fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        ioctl(fd, VIDIOC_G_FMT, &fmt);
    }

    char cc[5];
    fourcc_str(fmt.fmt.pix.pixelformat, cc);
    const uint32_t width = fmt.fmt.pix.width;
    const uint32_t height = fmt.fmt.pix.height;
    const bool use_ppa = (width == SRC_WIDTH && height == SRC_HEIGHT);
    if (!use_ppa) {
        ESP_LOGW(TAG, "采集分辨率 %ux%u 不是 %dx%d，跳过 PPA，直接按原尺寸编码",
                 width, height, SRC_WIDTH, SRC_HEIGHT);
    }
    const uint32_t enc_w = use_ppa ? OUT_WIDTH : width;
    const uint32_t enc_h = use_ppa ? OUT_HEIGHT : height;
    ESP_LOGI(TAG, "采集格式: %ux%u %s -> 编码 %ux%u", width, height, cc, enc_w, enc_h);

    /* PPA 硬件缩放：1080p RGB565 -> 720p RGB565（输出缓冲需按 cache line 对齐） */
    ppa_client_handle_t ppa = NULL;
    uint8_t *ppa_buf = NULL;
    if (use_ppa) {
        ppa_client_config_t ppa_cfg = {
            .oper_type = PPA_OPERATION_SRM,
        };
        if (ppa_register_client(&ppa_cfg, &ppa) != ESP_OK) {
            ESP_LOGE(TAG, "PPA 客户端注册失败");
            return;
        }
        uint32_t cap = enc_w * enc_h * 2;
        ppa_buf = esp_h264_aligned_calloc(128, 1, cap, &cap, ESP_H264_MEM_SPIRAM);
        if (!ppa_buf) {
            ESP_LOGE(TAG, "PPA 输出缓冲分配失败");
            return;
        }
        ESP_LOGI(TAG, "PPA 缩放就绪: %ux%u -> %ux%u (x%.4f)",
                 PPA_CROP_W, PPA_CROP_H, enc_w, enc_h, (double)PPA_SCALE);
    }

    /* 硬件 H.264 编码器：直接吃 RGB565 */
    esp_h264_enc_cfg_hw_t cfg = {
        .pic_type = ESP_H264_RAW_FMT_RGB565_LE,
        .gop      = 15,
        .fps      = TARGET_FPS,
        .res      = { .width = enc_w, .height = enc_h },
        // qp_max 必须放到 51（默认上限），否则码控无法在复杂场景把帧压到预算内，
        // 实测每帧会到 20KB（预算 9KB），必然顶爆 2.2Mbps 链路
        .rc       = { .bitrate = TARGET_BITRATE, .qp_min = 22, .qp_max = 51 },
    };
    esp_h264_enc_handle_t enc = NULL;
    ESP_ERROR_CHECK(esp_h264_enc_hw_new(&cfg, &enc) == ESP_H264_ERR_OK ? ESP_OK : ESP_FAIL);
    ESP_ERROR_CHECK(esp_h264_enc_open(enc) == ESP_H264_ERR_OK ? ESP_OK : ESP_FAIL);
    ESP_LOGI(TAG, "H.264 编码器就绪: %ux%u %dfps %dbps", enc_w, enc_h, TARGET_FPS, TARGET_BITRATE);

    uint32_t out_cap = enc_w * enc_h * 2;
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
    // 硬件编码器本身按传感器帧率出帧，配置里的 fps 不生效，需要主动丢帧。
    // 注意不能用固定时间间隔：传感器 45fps（帧周期 22ms）配 50ms 间隔会量化退化成 15fps。
    // 用累计器：每收一帧 acc += TARGET_FPS，累计满 SENSOR_FPS 就编码一帧，
    // 平均帧率精确等于 TARGET_FPS，抖动不超过一个传感器帧周期
    float acc = 0;

    while (1) {
        struct v4l2_buffer buf;
        memset(&buf, 0, sizeof(buf));
        buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buf.memory = V4L2_MEMORY_MMAP;
        if (ioctl(fd, VIDIOC_DQBUF, &buf) < 0) {
            vTaskDelay(pdMS_TO_TICKS(10));
            continue;
        }

        acc += TARGET_FPS;
        if (acc < SENSOR_FPS) {
            ioctl(fd, VIDIOC_QBUF, &buf);
            continue;
        }
        acc -= SENSOR_FPS;

        const void *enc_src = buffers[buf.index];
        if (use_ppa) {
            // 先让 PSRAM 里的旧数据失效，再由 PPA DMA 写入缩放结果
            esp_cache_msync(ppa_buf, enc_w * enc_h * 2, ESP_CACHE_MSYNC_FLAG_DIR_C2M);
            ppa_srm_oper_config_t srm = {
                .in = {
                    .buffer = buffers[buf.index],
                    .pic_w = width,
                    .pic_h = height,
                    .block_w = PPA_CROP_W,
                    .block_h = PPA_CROP_H,
                    .block_offset_x = PPA_OFF_X,
                    .block_offset_y = PPA_OFF_Y,
                    .srm_cm = PPA_SRM_COLOR_MODE_RGB565,
                },
                .out = {
                    .buffer = ppa_buf,
                    .buffer_size = enc_w * enc_h * 2,
                    .pic_w = enc_w,
                    .pic_h = enc_h,
                    .srm_cm = PPA_SRM_COLOR_MODE_RGB565,
                },
                .rotation_angle = PPA_SRM_ROTATION_ANGLE_0,
                .scale_x = PPA_SCALE,
                .scale_y = PPA_SCALE,
                // 注意：这里不能开 rgb_swap！实测编码器的 RGB565_LE 期望的字节序
                // 恰好与 ISP 输出一致；开 swap 反而会导致手机画面红蓝颠倒
                .mode = PPA_TRANS_MODE_BLOCKING,
            };
            if (ppa_do_scale_rotate_mirror(ppa, &srm) != ESP_OK) {
                errors++;
                ioctl(fd, VIDIOC_QBUF, &buf);
                continue;
            }
            enc_src = ppa_buf;
        }

#if DUMP_FRAME_ENABLE
        static int dump_n = 0;
        dump_n++;
        if (dump_n == 25 || dump_n == 600) {
            ESP_LOGW(TAG, "@@DUMP %d@@", dump_n);
            dump_frame((const uint8_t *)enc_src, enc_w, enc_h);
        }
#endif

        esp_h264_enc_in_frame_t in = {
            .raw_data = { .buffer = (void *)enc_src, .len = enc_w * enc_h * 2 },
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
