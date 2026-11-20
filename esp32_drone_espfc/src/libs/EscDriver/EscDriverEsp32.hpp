#ifndef HHHS_LIBS_ESCDRIVER_ESCDRIVERESP32_HPP_
#define HHHS_LIBS_ESCDRIVER_ESCDRIVERESP32_HPP_

#if defined(ESP32) && !defined(ESP32C3)

#include "EscDriver.hpp"
#include <driver/ledc.h>

// HuHuaShiZhe: LEDC based analog ESC driver (50Hz, 1-2ms).
// The upstream RMT driver targets an older ESP-IDF RMT LL API and no longer
// compiles with the ESP32 Arduino core 3.x, so this fork uses the LEDC
// peripheral which is the same path proven on the existing flight controller.
class EscDriverEsp32 : public EscDriverBase
{
public:
  EscDriverEsp32();
  int begin(const EscConfig& conf);
  void end();
  int attach(size_t channel, int pin, int pulse);
  int write(size_t channel, int pulse);
  void apply();
  int pin(size_t channel) const;
  uint32_t telemetry(size_t channel) const;

private:
  struct Slot
  {
    int pin = -1;
    int pulse = 1000;
    bool configured = false;
  };

  static constexpr size_t CHANNELS = ESC_CHANNEL_COUNT;
  static constexpr uint32_t DUTY_BITS = 14;
  static constexpr uint32_t DUTY_MAX = (1u << DUTY_BITS) - 1;

  uint32_t pulseToDuty(int pulse) const;

  Slot _channel[CHANNELS];
  int _timer = 0;
  int _rate = 50;
};

#endif
#endif // HHHS_LIBS_ESCDRIVER_ESCDRIVERESP32_HPP_
