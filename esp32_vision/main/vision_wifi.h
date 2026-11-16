/**
 * vision_wifi - WiFi STA 接入飞控热点（HuHuaShiZhe-Drone）
 *
 * 视觉板不自己开热点：手机连飞控AP，视觉板以STA身份加入同一网络，
 * 手机与视觉板在同一网段即可通过 UDP 8889 通信。
 */
#pragma once

#include <stdbool.h>
#include "esp_err.h"

esp_err_t vision_wifi_start(void);

/** 阻塞等待拿到IP（秒级超时），成功返回 true */
bool vision_wifi_wait_ip(int timeout_s);

/** 获取本机IP字符串（"192.168.x.x"），未连网返回 "0.0.0.0" */
const char *vision_wifi_ip_str(void);

/** 运行时切换 STA 目标网络（调试/测速用，不写入固件） */
esp_err_t vision_wifi_set_sta(const char *ssid, const char *pass);
