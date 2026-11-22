#ifndef HHHS_LIBS_ESPFC_ESPFC_HPP_
#define HHHS_LIBS_ESPFC_ESPFC_HPP_

#include "Blackbox/Blackbox.hpp"
#include "Connect/Buzzer.hpp"
#include "Control/Actuator.hpp"
#include "Control/Controller.hpp"
#include "Hardware.hpp"
#include "Input.hpp"
#include "Model.hpp"
#include "Output/Mixer.hpp"
#include "SensorManager.hpp"
#include "SerialManager.hpp"
#include "TelemetryManager.hpp"

namespace Espfc {

class Espfc
{
public:
  Espfc();

  int load();
  int begin();
  int update(bool externalTrigger = false);
  int updateOther();

  int getGyroInterval() const
  {
    return _model.state.gyro.timer.interval;
  }

  bool beginGyroTimer(Hal::HwTimer::Callback callback)
  {
    return _model.state.gyro.hwTimer.begin(getGyroInterval(), callback);
  }

  // 诊断用：传感器探测结果
  bool isGyroReady() const { return _model.state.gyro.present; }
  bool isAccelReady() const { return _model.state.accel.present; }
  bool isMagReady() const { return _model.state.mag.present; }
  bool isBaroReady() const { return _model.state.baro.present; }
  bool isGpsReady() const { return _model.state.gps.present; }
  bool isGpsFix() const { return _model.state.gps.fix; }
  int gpsSats() const { return _model.state.gps.numSats; }
  int gyroRate() const { return _model.state.gyro.timer.rate; }
  int baroPressure() const { return (int)_model.state.baro.pressure; }
  int baroAltitude10() const { return (int)(_model.state.baro.altitudeGround * 10.f); }
  int baroVario100() const { return (int)(_model.state.baro.vario * 100.f); }
  int magX() const { return _model.state.mag.raw.x; }
  int magY() const { return _model.state.mag.raw.y; }
  int magZ() const { return _model.state.mag.raw.z; }

private:
  Model _model;
  Hardware _hardware;
  Control::Controller _controller;
  TelemetryManager _telemetry;
  Input _input;
  Control::Actuator _actuator;
  SensorManager _sensor;
  Output::Mixer _mixer;
  Blackbox::Blackbox _blackbox;
  Connect::Buzzer _buzzer;
  SerialManager _serial;
  uint32_t _loop_next;
};

} // namespace Espfc
#endif // HHHS_LIBS_ESPFC_ESPFC_HPP_
