/**
 * vision_cam - OV5640 摄像头模块
 *
 * ★★★ 摄像头引脚映射：不同厂家 ESP32-S3-CAM 板接法不同！ ★★★
 * 下面是市面最常见的 S3-CAM N16R8 排插板引脚（大量第三方板通用）。
 * 如果 esp_camera_init 报 ESP_ERR_CAMERA_FAILED_TO_SENSOR / 黑屏 / 花屏，
 * 第一件事就是按你板子的引脚图核对并修改下面这组宏。
 */
#pragma once

#include "esp_err.h"
#include "esp_camera.h"

/** 支持的分辨率档位（下拉/命令索引对应此表顺序） */
typedef struct {
    const char *name;
    framesize_t fs;
} cam_res_t;

extern const cam_res_t k_cam_res[];
extern const int k_cam_res_count;

esp_err_t vision_cam_init(void);

/** 取一帧JPEG（fb->buf/fb->len），用完必须 cam_release(fb) */
camera_fb_t *cam_capture(void);
void cam_release(camera_fb_t *fb);

/** 设置推流分辨率档位（k_cam_res 索引），返回实际档位 */
int cam_set_stream_res(int res_idx);

/** 设置推流参数：fps（2~20）、JPEG质量（6最佳~25最差） */
void cam_set_stream_params(int fps, int quality);

int cam_get_fps(void);
int cam_get_quality(void);
int cam_get_stream_res(void);
const char *cam_sensor_name(void);

/** 图像翻转/镜像（装机方向不同时用） */
void cam_set_vflip(int on);
void cam_set_hmirror(int on);
