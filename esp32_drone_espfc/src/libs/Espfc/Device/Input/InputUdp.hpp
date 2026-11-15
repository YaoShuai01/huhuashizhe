#pragma once

#include "Device/InputDevice.hpp"
#include "Hal/Platform.hpp"
#include "Model.hpp"
#include <cstddef>
#include <cstdint>

#if defined(ESPFC_UDP_RX)

namespace Espfc::Device::Input {

// HuHuaShiZhe UDP RC input.
//
// Phone app K:V; protocol (port 8888):
//   ARM:1;PIT:0;ROL:0;THR:0;YAW:0;SPR:0
// THR is now a direct 0..100 throttle percentage from the vertical slider.
// MOTOR:1..4 is the web motor test, LAND:1 is an emergency disarm.
//
// Channels exposed to esp-fc (AETR order expected by the default channel map):
//   0 roll, 1 pitch, 2 throttle, 3 yaw, 4 aux1 (arm), 5 aux2 (angle mode)
class InputUdp : public InputDevice
{
public:
  explicit InputUdp(Model& model) : _model(model) {}
  int begin(void);
  InputStatus update() override;
  uint16_t get(uint8_t i) const override;
  void get(uint16_t* data, size_t len) const override;
  size_t getChannelCount() const override;
  bool needAverage() const override;

private:
  static constexpr size_t CHANNELS = 6;
  static void taskEntry(void* arg);
  void taskLoop();
  void parse(const char* buf, size_t len);
  void tick(uint32_t now);
  void publishChannels();
  void applySpray();
  void applyMotorTest(uint32_t now);
  void linkLost();

  Model& _model;
  volatile uint16_t _channels[CHANNELS] = {1500, 1500, 1000, 1500, 1000, 1800};
  volatile uint32_t _lastPacketMs = 0;
  volatile uint32_t _packets = 0;
  volatile bool _newFrame = false;
  bool _linked = false;

  // latest app command
  int _appRoll = 0;
  int _appPitch = 0;
  int _appThrottle = 0; // 0..100 direct throttle
  int _appYaw = 0;
  int _sprayLevel = 0;
  int _motorTest = 0;
  uint32_t _motorTestUntil = 0;
  bool _armCmd = false;
  bool _disarmLatch = false;
  uint16_t _throttle = 1000;

  static constexpr uint16_t THROTTLE_MIN = 1000;
  static constexpr uint16_t THROTTLE_MAX = 2000;
  static constexpr uint16_t ARM_ON = 1800;
  static constexpr uint16_t ARM_OFF = 1000;
  static constexpr uint16_t ANGLE_ON = 1800;
  static constexpr uint32_t LINK_TIMEOUT_MS = 300;
};

} // namespace Espfc::Device::Input

#endif
