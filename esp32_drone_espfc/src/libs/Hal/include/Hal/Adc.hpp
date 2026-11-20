#ifndef HHHS_LIBS_HAL_INCLUDE_HAL_ADC_HPP_
#define HHHS_LIBS_HAL_INCLUDE_HAL_ADC_HPP_

#include <cstdint>

namespace Hal {

class Adc
{
public:
  static void begin(uint8_t pin);
  static uint16_t read(uint8_t pin);
};

} // namespace Hal
#endif // HHHS_LIBS_HAL_INCLUDE_HAL_ADC_HPP_
