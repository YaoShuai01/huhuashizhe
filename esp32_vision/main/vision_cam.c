/**
 * vision_cam - OV5640 摄像头模块实现
 */
#include <string.h>
#include "esp_log.h"
#include "vision_cam.h"

static const char *TAG = "VCAM";

// ==================== 引脚映射（按板子改这里） ====================
#define CAM_PIN_PWDN   -1
#define CAM_PIN_RESET  -1
#define CAM_PIN_XCLK   15
#define CAM_PIN_SIOD   4
#define CAM_PIN_SIOC   5

#define CAM_PIN_D0     11
#define CAM_PIN_D1     9
#define CAM_PIN_D2     8
#define CAM_PIN_D3     10
#define CAM_PIN_D4     12
#define CAM_PIN_D5     18
#define CAM_PIN_D6     17
#define CAM_PIN_D7     16

#define CAM_PIN_VSYNC  6
#define CAM_PIN_HREF   7
#define CAM_PIN_PCLK   13

// ==================== 分辨率档位表 ====================
const cam_res_t k_cam_res[] = {
    { "VGA",   FRAMESIZE_VGA   },  // 0: 640x480
    { "SVGA",  FRAMESIZE_SVGA  },  // 1: 800x600
    { "XGA",   FRAMESIZE_XGA   },  // 2: 1024x768（推流默认）
    { "HD",    FRAMESIZE_HD    },  // 3: 1280x720
    { "SXGA",  FRAMESIZE_SXGA  },  // 4: 1280x1024
    { "UXGA",  FRAMESIZE_UXGA  },  // 5: 1600x1200
    { "QXGA",  FRAMESIZE_QXGA  },  // 6: 2048x1536
    { "QSXGA", FRAMESIZE_QSXGA },  // 7: 2560x1920（OV5640 五百万档）
};
const int k_cam_res_count = sizeof(k_cam_res) / sizeof(k_cam_res[0]);

// ==================== 默认推流档位 ====================
// 档位索引对应 k_cam_res[]：0=VGA 1=SVGA 2=XGA 3=HD 4=SXGA 5=UXGA 6=QXGA 7=QSXGA
//
// ★ 不要改回 2(XGA) 或更大。这是实测出来的工作点，不是随便选的：
//
//   2026-11 实测（ESP32-S3 N16R8 + OV5640，纯AP，MCS7/HT40，20MHz XCLK）
//   ---------------------------------------------------------------
//   VGA  640x480   采集 22.2fps   UDP 194 KB/s
//   XGA  1024x768  采集 19.4fps   UDP 510 KB/s
//   HD   1280x720  采集 20.0fps   UDP 386 KB/s   ← 帧率与码率的平衡点
//   UXGA 1600x1200 采集  4.6fps   UDP 151 KB/s   ← 断崖，别用
//   QSXGA 2560x1920 采集 4.6fps   UDP 126 KB/s   ← 同上
//
// UXGA 及以上单帧接近 1MB，DMA 搬运 + JPEG 编码的固定开销把帧率压到
// 4.6fps，与分辨率无关（UXGA 和 QSXGA 都是 4.6），说明撞的是物理上限，
// 不是配置问题。要看 5MP 细节请用拍照（VSNAP，实测 2560x1920 成功），
// 不要试图提高推流分辨率。
//
// 帧率填 20 而不是 25：HD 档实测能跑满 20fps，填更高只会让 capture_task
// 空转等待，不会真的更快。
#define STREAM_RES_DEFAULT 3   // HD 1280x720
#define STREAM_FPS_DEFAULT 20
#define STREAM_Q_DEFAULT   12

static bool s_inited = false;
static int  s_stream_res = STREAM_RES_DEFAULT;
static int  s_fps = STREAM_FPS_DEFAULT;
static int  s_quality = STREAM_Q_DEFAULT;

static void clamp_stream_res(void)
{
    // QSXGA 单帧约 150KB，按 12fps 推流要 1.8MB/s，WiFi 扛不住，所以
    // 【推流档位】封顶 UXGA。但拍照是一次性的，150KB 毫无压力，不受此限——
    // 见 cam_set_snapshot_res()。
    if (s_stream_res > 5) s_stream_res = 5;
    if (s_stream_res < 0) s_stream_res = 0;
}

esp_err_t vision_cam_init(void)
{
    if (s_inited) return ESP_OK;

    camera_config_t config = {
        .pin_pwdn  = CAM_PIN_PWDN,
        .pin_reset = CAM_PIN_RESET,
        .pin_xclk  = CAM_PIN_XCLK,
        .pin_sccb_sda = CAM_PIN_SIOD,
        .pin_sccb_scl = CAM_PIN_SIOC,

        .pin_d7 = CAM_PIN_D7,
        .pin_d6 = CAM_PIN_D6,
        .pin_d5 = CAM_PIN_D5,
        .pin_d4 = CAM_PIN_D4,
        .pin_d3 = CAM_PIN_D3,
        .pin_d2 = CAM_PIN_D2,
        .pin_d1 = CAM_PIN_D1,
        .pin_d0 = CAM_PIN_D0,
        .pin_vsync = CAM_PIN_VSYNC,
        .pin_href  = CAM_PIN_HREF,
        .pin_pclk  = CAM_PIN_PCLK,

        // ★ XCLK 必须是 80MHz 的整数分频，别贪"更高像素吞吐"换成 24MHz。
        //
        // ESP32-S3 的 XCLK 从 80MHz 时钟分频得到（见 ESP-FAQ），分频不整除会
        // 产生时钟抖动，DVP 采样不稳、帧率忽高忽低。可选值只有
        // 80/1=80, 80/2=40, 80/4=20, 80/5=16, 80/8=10, 80/3=26.67 …
        // 旧配置用的 24MHz（80/24=3.333）不整除，注释里"提升约20%像素吞吐"
        // 的说法在分频抖动下并不成立。
        // 20MHz 是 esp32-camera 官方例程默认值，也是实测工作点。
        .xclk_freq_hz = 20000000,
        .ledc_timer   = LEDC_TIMER_0,
        .ledc_channel = LEDC_CHANNEL_0,

        .pixel_format = PIXFORMAT_JPEG,
        // ★ 帧缓冲按最大分辨率(QSXGA 5MP)分配：esp32-camera 的缓冲大小在
        //   初始化后固定，运行中 set_framesize 升档超过初始分配会出帧失败。
        //   初始化完立刻降回推流分辨率，后续拍照升档才有缓冲可用。
        //
        //   注意这同时决定了 DMA 搬运缓冲的大小（见 sdkconfig.defaults 里
        //   CONFIG_CAMERA_PSRAM_DMA 的说明）：按 QSXGA 算出的约 960KB 是
        //   大 JPEG 能被完整搬完的前提。改成小分辨率会让复杂画面丢帧尾。
        .frame_size   = FRAMESIZE_QSXGA,
        .jpeg_quality = s_quality,
        // ★ fb_count 保持 2，别为了"更多缓冲更流畅"改成 3 或更大。
        //
        // CAMERA_GRAB_LATEST 下应用层实际只能拿到 fb_count-1 帧（驱动自己
        // 占一帧持续刷新最新数据），所以 3 并不会让流水线更顺，只是多占
        // 一帧 PSRAM —— 按 QSXGA 初始化算是每帧 984KB，纯浪费，还会和
        // WiFi 的 PSRAM DMA 抢带宽。
        .fb_count     = 2,
        .grab_mode    = CAMERA_GRAB_LATEST,
        .fb_location  = CAMERA_FB_IN_PSRAM,
        .sccb_i2c_port = 0,
    };

    esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "摄像头初始化失败 0x%x", err);
        ESP_LOGE(TAG, "→ 90%%是引脚映射不对，请核对 vision_cam.c 顶部 CAM_PIN_* 宏");
        ESP_LOGE(TAG, "→ 也检查OV5640排线是否插紧、方向是否正确");
        return err;
    }

    sensor_t *s = esp_camera_sensor_get();
    if (s) {
        ESP_LOGI(TAG, "传感器: %s PID=0x%04x",
                 (s->id.PID == 0x5640) ? "OV5640" : "其他", s->id.PID);
        // 缓冲按QSXGA分配完毕，降回推流分辨率
        s->set_framesize(s, k_cam_res[s_stream_res].fs);
        // OV5640 默认开自动曝光/AWB，白平衡稍慢可按需关
    }
    s_inited = true;
    ESP_LOGI(TAG, "摄像头就绪（推流 %s %dfps q%d）",
             k_cam_res[s_stream_res].name, s_fps, s_quality);
    return ESP_OK;
}

camera_fb_t *cam_capture(void)
{
    if (!s_inited) return NULL;
    return esp_camera_fb_get();
}

void cam_release(camera_fb_t *fb)
{
    if (fb) esp_camera_fb_return(fb);
}

int cam_set_stream_res(int res_idx)
{
    if (res_idx < 0 || res_idx >= k_cam_res_count) return -1;
    s_stream_res = res_idx;
    clamp_stream_res();

    sensor_t *s = esp_camera_sensor_get();
    if (s) {
        // ★ set_framesize 内部会重置传感器的 flip/mirror 寄存器，
        //   必须先保存再恢复，否则切换分辨率/拍照后画面翻转就丢了，
        //   会出现"图传翻转了但拍照没翻转"的不一致
        const int vf = s->status.vflip;
        const int hm = s->status.hmirror;
        s->set_framesize(s, k_cam_res[s_stream_res].fs);
        s->set_vflip(s, vf);
        s->set_hmirror(s, hm);
    }
    ESP_LOGI(TAG, "推流分辨率 → %s", k_cam_res[s_stream_res].name);
    return s_stream_res;
}

/// 切到拍照分辨率（不受推流 clamp 限制，可到 QSXGA 5MP）。
/// 返回实际生效的档位索引；失败返回 -1。
int cam_set_snapshot_res(int res_idx)
{
    if (res_idx < 0 || res_idx >= k_cam_res_count) return -1;

    sensor_t *s = esp_camera_sensor_get();
    if (s) {
        const int vf = s->status.vflip;
        const int hm = s->status.hmirror;
        s->set_framesize(s, k_cam_res[res_idx].fs);
        s->set_vflip(s, vf);
        s->set_hmirror(s, hm);
    }
    ESP_LOGI(TAG, "拍照分辨率 → %s", k_cam_res[res_idx].name);
    return res_idx;
}

void cam_set_stream_params(int fps, int quality)
{
    if (fps >= 2 && fps <= 30)  s_fps = fps;
    if (quality >= 6 && quality <= 25) s_quality = quality;

    sensor_t *s = esp_camera_sensor_get();
    if (s) s->set_quality(s, s_quality);
    ESP_LOGI(TAG, "推流参数 → %dfps q%d", s_fps, s_quality);
}

int cam_set_fps_only(int fps)
{
    if (fps < 2) fps = 2;
    if (fps > 30) fps = 30;
    if (fps == s_fps) return s_fps;
    s_fps = fps;
    return s_fps;
}

int cam_set_quality_only(int quality)
{
    if (quality < 6) quality = 6;
    if (quality > 25) quality = 25;
    // 变化小于 2 级不重配传感器：set_quality 会触发一次寄存器写入，
    // 高频调用反而干扰出帧节奏。
    if (quality == s_quality || (quality > s_quality && quality - s_quality < 2) ||
        (quality < s_quality && s_quality - quality < 2)) {
        return s_quality;
    }
    s_quality = quality;
    sensor_t *s = esp_camera_sensor_get();
    if (s) s->set_quality(s, s_quality);
    return s_quality;
}

int cam_set_preview_res(int res_idx)
{
    if (res_idx < 0 || res_idx >= k_cam_res_count) return -1;

    // 只动传感器，不改 s_stream_res —— 网页预览结束后 UDP 推流档位
    // 记录必须保持原值，否则 VINFO/收流端会误判。
    sensor_t *s = esp_camera_sensor_get();
    if (s) {
        const int vf = s->status.vflip;
        const int hm = s->status.hmirror;
        s->set_framesize(s, k_cam_res[res_idx].fs);
        s->set_vflip(s, vf);
        s->set_hmirror(s, hm);
    }
    return res_idx;
}

int cam_get_fps(void)          { return s_fps; }
int cam_get_quality(void)      { return s_quality; }
int cam_get_stream_res(void)   { return s_stream_res; }

const char *cam_sensor_name(void)
{
    // esp32-camera v2 的 sensor_t 没有 name 成员，用 PID 映射
    sensor_t *s = esp_camera_sensor_get();
    if (!s) return "unknown";
    switch (s->id.PID) {
        case 0x5640: return "OV5640";
        case 0x2640: return "OV2640";
        case 0x3660: return "OV3660";
        case 0x3630: return "OV3630";
        case 0x7740: return "OV7740";
        case 0x9740: return "OV9740";
        default:     return "unknown";
    }
}

void cam_set_vflip(int on)
{
    sensor_t *s = esp_camera_sensor_get();
    if (s) s->set_vflip(s, on ? 1 : 0);
}

void cam_set_hmirror(int on)
{
    sensor_t *s = esp_camera_sensor_get();
    if (s) s->set_hmirror(s, on ? 1 : 0);
}
