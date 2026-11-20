#ifndef HHHS_LIBS_ESPFC_SENSOR_MAGSENSOR_HPP_
#define HHHS_LIBS_ESPFC_SENSOR_MAGSENSOR_HPP_

#include "BaseSensor.hpp"
#include "Device/MagDevice.hpp"
#include "Model.hpp"

namespace Espfc::Sensor {

class MagSensor : public BaseSensor
{
public:
  MagSensor(Model& model);

  int begin();
  int reload(ModelChangeEvent event);
  int update();
  int read();
  int filter();

private:
  void calibrate();
  void resetCalibration();
  void updateCalibration();
  void applyCalibration();

  Model& _model;
  Device::MagDevice* _mag;
};

} // namespace Espfc::Sensor
#endif // HHHS_LIBS_ESPFC_SENSOR_MAGSENSOR_HPP_
