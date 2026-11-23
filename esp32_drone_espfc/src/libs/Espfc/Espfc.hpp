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
#include "Utils/Math.hpp"

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

  // 偏航闭环诊断：判断修正方向是否真的在抵消自旋
  bool isArmed() const { return _model.isModeActive(MODE_ARMED); }
  float gyroYawDeg() const { return Utils::toDeg(_model.state.gyro.adc[AXIS_YAW]); }
  float setpointYawDeg() const { return Utils::toDeg(_model.state.setpoint.rate[AXIS_YAW]); }
  float outputYaw() const { return _model.state.output.ch[AXIS_YAW]; }
  int motorUs(int i) const { return (i >= 0 && i < 4) ? (int)_model.state.output.us[i] : 0; }

  // 飞行日志：格式化为一行 CSV（角度/角速度单位 0.1，输出为 0.001 满量程）
  int logFlight(uint32_t ms, char* buf, size_t len)
  {
    const auto& s = _model.state;
    const int gx = (int)(Utils::toDeg(s.gyro.adc[AXIS_ROLL]) * 10.f);
    const int gy = (int)(Utils::toDeg(s.gyro.adc[AXIS_PITCH]) * 10.f);
    const int gz = (int)(Utils::toDeg(s.gyro.adc[AXIS_YAW]) * 10.f);
    const int sx = (int)(Utils::toDeg(s.setpoint.rate[AXIS_ROLL]) * 10.f);
    const int sy = (int)(Utils::toDeg(s.setpoint.rate[AXIS_PITCH]) * 10.f);
    const int sz = (int)(Utils::toDeg(s.setpoint.rate[AXIS_YAW]) * 10.f);
    const int ox = (int)(s.output.ch[AXIS_ROLL] * 1000.f);
    const int oy = (int)(s.output.ch[AXIS_PITCH] * 1000.f);
    const int oz = (int)(s.output.ch[AXIS_YAW] * 1000.f);
    return snprintf(buf, len, "%lu,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
                    (unsigned long)ms, isArmed() ? 1 : 0, gx, gy, gz, sx, sy, sz, ox, oy, oz,
                    (int)s.input.us[AXIS_ROLL], (int)s.input.us[AXIS_PITCH], (int)s.input.us[AXIS_THRUST],
                    (int)s.input.us[AXIS_YAW], motorUs(0), motorUs(1), motorUs(2), motorUs(3),
                    (int)(s.baro.altitudeGround * 100.f), (int)(s.baro.vario * 100.f), (int)s.gps.numSats);
  }

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
