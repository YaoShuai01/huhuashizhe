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

#define STREAM_RES_DEFAULT 2   // XGA
#define STREAM_FPS_DEFAULT 12
#define STREAM_Q_DEFAULT   12

static bool s_inited = false;
static int  s_stream_res = STREAM_RES_DEFAULT;
static int  s_fps = STREAM_FPS_DEFAULT;
static int  s_quality = STREAM_Q_DEFAULT;

static void clamp_stream_res(void)
{
    // QSXGA 单帧太大不适合推流，推流档位封顶 UXGA
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

        .xclk_freq_hz = 20000000,
        .ledc_timer   = LEDC_TIMER_0,
        .ledc_channel = LEDC_CHANNEL_0,

        .pixel_format = PIXFORMAT_JPEG,
        .frame_size   = k_cam_res[s_stream_res].fs,
        .jpeg_quality = s_quality,
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
    if (s) s->set_framesize(s, k_cam_res[s_stream_res].fs);
    ESP_LOGI(TAG, "推流分辨率 → %s", k_cam_res[s_stream_res].name);
    return s_stream_res;
}

void cam_set_stream_params(int fps, int quality)
{
    if (fps >= 2 && fps <= 20)  s_fps = fps;
    if (quality >= 6 && quality <= 25) s_quality = quality;

    sensor_t *s = esp_camera_sensor_get();
    if (s) s->set_quality(s, s_quality);
    ESP_LOGI(TAG, "推流参数 → %dfps q%d", s_fps, s_quality);
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
