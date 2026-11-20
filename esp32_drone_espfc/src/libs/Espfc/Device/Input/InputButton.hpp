#ifndef HHHS_LIBS_ESPFC_DEVICE_INPUT_INPUTBUTTON_HPP_
#define HHHS_LIBS_ESPFC_DEVICE_INPUT_INPUTBUTTON_HPP_

namespace Espfc::Device::Input {

class InputButton
{
public:
  int begin(int pin, bool triggerLow = true);
  int update();

private:
  int _result = 0; // bit 0: one click, 1: double click, 2: long press
  int _pin = -1;
  bool _triggerLow = true;
};

} // namespace Espfc::Device::Input
#endif // HHHS_LIBS_ESPFC_DEVICE_INPUT_INPUTBUTTON_HPP_
