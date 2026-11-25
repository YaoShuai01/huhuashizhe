#pragma once

// P4 → 飞控 SPI 图传桥：接收 H.264 NAL，按 1400 字节分段 UDP 单播给手机 APP
void videoBridgeBegin();

// espfc.begin() 启动 WiFi AP 后由 main.cpp 置位。
// 图传任务必须等它为真才能建 socket：lwIP 未初始化时 socket 调用会断言重启。
extern volatile bool g_wifiReady;
