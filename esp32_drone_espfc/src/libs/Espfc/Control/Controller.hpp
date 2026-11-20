#ifndef HHHS_LIBS_ESPFC_CONTROL_CONTROLLER_HPP_
#define HHHS_LIBS_ESPFC_CONTROL_CONTROLLER_HPP_

#include "Control/Rates.hpp"
#include "Model.hpp"

namespace Espfc::Control {

class Controller
{
public:
  Controller(Model& model);
  int begin();
  int reload(ModelChangeEvent event);
  int update();

  void outerLoopRobot();
  void innerLoopRobot();
  void outerLoop();
  void innerLoop();

  inline float getTpaFactor() const;
  inline void resetIterm();
  float calculateSetpointRate(int axis, float input) const;
  float calcualteAltHoldSetpoint() const;

  // 水平微调：在角度模式下给 roll/pitch 角目标叠加固定偏移（弧度）。
  // 由地面站/APP 写入，飞控重启后由 InputUdp 从 NVS 恢复。
  static void setTrim(int axis, float radians);
  static float getTrim(int axis);

private:
  void reloadFilter();
  void reloadPid();

  Model& _model;
  Rates _rates;
  Utils::Filter _speedFilter;
};

} // namespace Espfc::Control
#endif // HHHS_LIBS_ESPFC_CONTROL_CONTROLLER_HPP_
