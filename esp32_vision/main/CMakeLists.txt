idf_component_register(SRCS "main.c"
                            "vision_wifi.c"
                            "vision_cam.c"
                            "vision_udp.c"
                            "vision_http.c"
                            "vision_serial.c"
                            "vision_led.c"
                    INCLUDE_DIRS "."
                    REQUIRES esp_wifi nvs_flash esp_netif esp_timer esp_psram driver esp_driver_usb_serial_jtag)
