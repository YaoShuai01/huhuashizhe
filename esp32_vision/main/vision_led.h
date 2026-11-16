/**
 * vision_led - 板载 WS2812 全彩灯状态指示
 * GPIO48；2 秒周期内白、红两次快速频闪
 */
#pragma once

#include "esp_err.h"

esp_err_t vision_led_start(void);
