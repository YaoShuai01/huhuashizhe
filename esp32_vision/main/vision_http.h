/**
 * vision_http - 浏览器图传窗口（MJPEG over HTTP，端口 80）
 *
 * 电脑/手机连接视觉板热点 HuHuaShiZhe-CAM（或同一飞控热点）后，浏览器打开：
 *   http://192.168.5.1            —— 实时画面 + 拍照链接（体验页）
 *   http://192.168.5.1/stream     —— 纯 MJPEG 流（XGA，与推流参数一致）
 *   http://192.168.5.1/capture    —— 500万像素 QSXGA(2560x1920) 单张照片
 *   http://192.168.5.1/capture?res=5 —— 指定分辨率拍照（k_cam_res 索引）
 *
 * 体验用途：MJPEG 流与 UDP 推流并发时共享帧缓冲，偶有抽帧属正常。
 */
#pragma once

#include "esp_err.h"

esp_err_t vision_http_start(void);
