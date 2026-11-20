#ifndef HHHS_LIBS_HAL_INCLUDE_HAL_RGBLED_HPP_
#define HHHS_LIBS_HAL_INCLUDE_HAL_RGBLED_HPP_

#include <cstdint>

namespace Hal {

struct RgbColor
{
  uint8_t r = 0;
  uint8_t g = 0;
  uint8_t b = 0;
};

class RgbLed
{
public:
  void begin(int8_t pin);
  void write(const RgbColor& color);

private:
  int8_t _pin = -1;
};

} // namespace Hal
#endif // HHHS_LIBS_HAL_INCLUDE_HAL_RGBLED_HPP_
