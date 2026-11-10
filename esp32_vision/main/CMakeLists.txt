idf_component_register(SRCS "main.c"
                            "vision_wifi.c"
                            "vision_cam.c"
                            "vision_udp.c"
                            "vision_http.c"
                            "vision_serial.c"
                    INCLUDE_DIRS "."
                    REQUIRES esp_wifi nvs_flash esp_netif esp_timer esp_psram driver)
