idf_component_register(SRCS "main.c"
                       INCLUDE_DIRS "."
                       REQUIRES example_video_common esp_video esp_timer nvs_flash
                                esp_driver_usb_serial_jtag esp_h264 esp_driver_ppa esp_mm)
