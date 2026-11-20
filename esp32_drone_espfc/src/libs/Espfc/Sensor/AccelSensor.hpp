#ifndef HHHS_LIBS_ESPFC_SENSOR_ACCELSENSOR_HPP_
#define HHHS_LIBS_ESPFC_SENSOR_ACCELSENSOR_HPP_

#include "Device/GyroDevice.hpp"
#include "Model.hpp"
#include "Sensor/BaseSensor.hpp"

namespace Espfc::Sensor {

class AccelSensor : public BaseSensor
{
public:
  AccelSensor(Model& model);

  int begin();
  int reload(ModelChangeEvent event);
  int update();
  int read();
  int filter();

private:
  void calibrate(VectorFloat& accel);

  Model& _model;
  Device::GyroDevice* _gyro;
  Utils::Filter _filter[AXIS_COUNT_RPY];
};

} // namespace Espfc::Sensor
#endif // HHHS_LIBS_ESPFC_SENSOR_ACCELSENSOR_HPP_
