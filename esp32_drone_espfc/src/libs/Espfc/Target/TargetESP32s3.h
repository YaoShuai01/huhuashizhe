#pragma once

// HuHuaShiZhe flight controller pin map (ESP32-S3)
// pins to avoid:
// strapping: 0, 3, 45, 46
// flash/psram: 26-37
// usb/jtag: 19, 20

#define ESPFC_INPUT
#define ESPFC_INPUT_PIN 6 // ppm (not used)

// Betaflight Quad X motor order: output 0=RR, 1=FR, 2=RL, 3=FL
// Existing airframe wiring: FR=GPIO1, FL=GPIO4, BR=GPIO21, BL=GPIO12
#define ESPFC_OUTPUT_COUNT 4
#define ESPFC_OUTPUT_0 21 // RR (rear right)  -> BR
#define ESPFC_OUTPUT_1 1  // FR (front right) -> FR
#define ESPFC_OUTPUT_2 12 // RL (rear left)   -> BL
#define ESPFC_OUTPUT_3 4  // FL (front left)  -> FL

// CH343 / UART0 port for Betaflight Configurator
#define ESPFC_SERIAL_0
#define ESPFC_SERIAL_0_TX 43
#define ESPFC_SERIAL_0_RX 44
#define ESPFC_SERIAL_0_FN (SERIAL_FUNCTION_MSP)
#define ESPFC_SERIAL_0_BAUD (SERIAL_SPEED_115200)
#define ESPFC_SERIAL_0_BBAUD (SERIAL_SPEED_NONE)

// Native USB port, also MSP
#define ESPFC_SERIAL_USB
#define ESPFC_SERIAL_USB_FN (SERIAL_FUNCTION_MSP)
#define ESPFC_SERIAL_USB_REENUMERATE

#define ESPFC_SERIAL_REMAP_PINS
#define ESPFC_SERIAL_DEBUG_PORT SERIAL_USB

// MPU6050 wiring confirmed by user: SDA=GPIO41, SCL=GPIO42 (hardware I2C)
#define ESPFC_I2C_0
#define ESPFC_I2C_0_SCL 42
#define ESPFC_I2C_0_SDA 41

#define ESPFC_BUZZER_PIN -1
#define ESPFC_BUTTON_PIN -1
#define ESPFC_LED_PIN -1

// motors stop at zero throttle, no serial receiver feature (UDP input is always present)
#define ESPFC_FEATURE_MASK (FEATURE_MOTOR_STOP)

// 100kHz soft I2C cannot sustain 1kHz; 500Hz gyro / 250Hz PID is safe.
#define ESPFC_GYRO_I2C_RATE_MAX 500
#define ESPFC_GYRO_SPI_RATE_MAX 4000
