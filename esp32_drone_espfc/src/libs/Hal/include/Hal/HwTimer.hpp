#ifndef HHHS_LIBS_HAL_INCLUDE_HAL_HWTIMER_HPP_
#define HHHS_LIBS_HAL_INCLUDE_HAL_HWTIMER_HPP_

#include <cstdint>

namespace Hal {

// Periodic hardware timer, the callback runs in interrupt context and must be placed in fast memory.
class HwTimer
{
public:
  // Return true when a higher priority task was woken and a context switch is required on ISR exit.
  using Callback = bool (*)(void* arg);

  // TODO: operator= which stops the timer
  constexpr explicit HwTimer(uint8_t id = 0): _callback(nullptr), _arg(nullptr), _interval(0), _id(id), _running(false), _handle(nullptr)
  {
  }

  bool begin(uint32_t intervalUs, Callback callback, void* arg = nullptr);
  void end();

  bool isRunning() const
  {
    return _running;
  }

private:
  Callback _callback;
  void* _arg;
  uint32_t _interval;
  uint8_t _id;
  bool _running;
  void* _handle;
};

} // namespace Hal
#endif // HHHS_LIBS_HAL_INCLUDE_HAL_HWTIMER_HPP_
