#ifndef HHHS_LIBS_ESPFC_SENSOR_BASESENSOR_HPP_
#define HHHS_LIBS_ESPFC_SENSOR_BASESENSOR_HPP_

#include <cstdint>
#include <helper_3dmath.hpp>

namespace Espfc::Sensor {

class BaseSensor
{
public:
  void align(VectorFloat& dest, uint8_t rotation);
  void toVector(VectorInt16& v, uint8_t* buf);
};

} // namespace Espfc::Sensor
#endif // HHHS_LIBS_ESPFC_SENSOR_BASESENSOR_HPP_
