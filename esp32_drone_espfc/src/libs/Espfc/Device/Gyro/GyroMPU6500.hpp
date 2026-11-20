#ifndef HHHS_LIBS_ESPFC_DEVICE_GYRO_GYROMPU6500_HPP_
#define HHHS_LIBS_ESPFC_DEVICE_GYRO_GYROMPU6500_HPP_

#include "GyroMPU6050.hpp"

namespace Espfc::Device::Gyro {

class GyroMPU6500 : public GyroMPU6050
{
public:
  GyroDeviceType getType() const override;

  void setDLPFMode(uint8_t mode) override;

  bool testConnection() override;
};

} // namespace Espfc::Device::Gyro
#endif // HHHS_LIBS_ESPFC_DEVICE_GYRO_GYROMPU6500_HPP_
