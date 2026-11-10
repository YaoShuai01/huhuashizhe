/**
 * vision_serial - 串口图传（USB-UART 口，CH343，最高 3M 波特率）
 *
 * 用途：电脑用 USB 线直连视觉板，无需任何网络即可看实时画面。
 * 与控制台日志共用 UART0，因此推流期间自动静默日志，停止后恢复。
 *
 * 协议（帧）：'H''V' + type + len32(LE) + JPEG数据
 *   type 0x03 = 实时流帧(XGA)；type 0x04 = 高清拍照(QSXGA 5MP)
 *
 * 命令（文本行，115200 或 3M 均可发）：
 *   VSS  开始实时流：回 "VOK SS"（115200）→ 双方切 3M → 持续发 0x03 帧
 *   VSE  停止：切回 115200，回 "VOK SE"
 *   VS1  500万像素拍照(QSXGA)：需先 VSS，回 0x04 帧（约800KB，3M下约3秒）
 *
 * 典型帧率：3M 波特率下 XGA 约 4~6 fps
 */
#pragma once

#include "esp_err.h"

esp_err_t vision_serial_start(void);
