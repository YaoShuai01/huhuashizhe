#ifndef HHHS_LIBS_HAL_INCLUDE_HAL_TIME_HPP_
#define HHHS_LIBS_HAL_INCLUDE_HAL_TIME_HPP_

#include <cstdint>

extern "C" {

// forward declaration to Arduino functions
#if defined(UNIT_TEST) || defined(ESP8266) || defined(ARCH_RP2040)
void delay(unsigned long ms);
void delayMicroseconds(unsigned int us);
#else
void delay(uint32_t ms);
void delayMicroseconds(uint32_t us);
#endif

unsigned long micros();
unsigned long millis();

} // extern "C"
#endif // HHHS_LIBS_HAL_INCLUDE_HAL_TIME_HPP_
