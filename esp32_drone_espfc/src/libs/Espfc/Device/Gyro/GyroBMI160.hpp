#ifndef HHHS_LIBS_ESPFC_DEVICE_GYRO_GYROBMI160_HPP_
#define HHHS_LIBS_ESPFC_DEVICE_GYRO_GYROBMI160_HPP_

#include "Device/GyroDevice.hpp"
#include "helper_3dmath.hpp"

namespace Espfc::Device::Gyro {

class GyroBMI160 : public GyroDevice
{
public:
  int begin(Hal::BusDevice* bus) override;
  int begin(Hal::BusDevice* bus, uint8_t addr) override;

  GyroDeviceType getType() const override;

  int readGyro(VectorInt16& v) override;
  int readAccel(VectorInt16& v) override;

  void setDLPFMode(uint8_t mode) override;

  int getRate() const override;

  void setRate(int rate) override;

  bool testConnection() override;
};

} // namespace Espfc::Device::Gyro
#endif // HHHS_LIBS_ESPFC_DEVICE_GYRO_GYROBMI160_HPP_
