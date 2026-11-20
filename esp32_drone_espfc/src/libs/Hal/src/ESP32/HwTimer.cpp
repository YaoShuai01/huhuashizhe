#if defined(ESP32)

#include "Hal/HwTimer.hpp"
#include <driver/gptimer.h>
#include <esp_attr.h>
#include <soc/soc_caps.h>

namespace Hal {

namespace {

// gptimer (driver_ng) 是新驱动；旧版 driver/timer.h 会与 esp_timer / Arduino 已占用的
// 定时器组中断冲突并 abort（timer_group: CONFLICT!），因此这里全部走新 API。
constexpr uint8_t MAX_TIMERS = SOC_TIMER_GROUP_TOTAL_TIMERS;

struct TimerSlot
{
  HwTimer::Callback callback;
  void* arg;
};

TimerSlot slots[MAX_TIMERS] = {};

bool IRAM_ATTR onAlarm(gptimer_handle_t timer, const gptimer_alarm_event_data_t* edata, void* userCtx)
{
  (void)timer;
  (void)edata;
  const uintptr_t idx = reinterpret_cast<uintptr_t>(userCtx);
  if (idx >= MAX_TIMERS) return false;
  TimerSlot& slot = slots[idx];
  if (!slot.callback) return false;
  return slot.callback(slot.arg);
}

} // namespace

bool HwTimer::begin(uint32_t intervalUs, Callback callback, void* arg)
{
  if (_running || !callback || !intervalUs || _id >= MAX_TIMERS) return false;

  _callback = callback;
  _arg = arg;
  _interval = intervalUs;

  slots[_id].callback = callback;
  slots[_id].arg = arg;

  gptimer_config_t cfg = {};
  cfg.clk_src = GPTIMER_CLK_SRC_DEFAULT;
  cfg.direction = GPTIMER_COUNT_UP;
  cfg.resolution_hz = 1000000; // 1 tick == 1us

  gptimer_handle_t handle = nullptr;
  if (gptimer_new_timer(&cfg, &handle) != ESP_OK)
  {
    slots[_id].callback = nullptr;
    slots[_id].arg = nullptr;
    return false;
  }

  gptimer_event_callbacks_t cbs = {};
  cbs.on_alarm = onAlarm;
  void* userCtx = reinterpret_cast<void*>(static_cast<uintptr_t>(_id));
  if (gptimer_register_event_callbacks(handle, &cbs, userCtx) != ESP_OK)
  {
    gptimer_del_timer(handle);
    slots[_id].callback = nullptr;
    slots[_id].arg = nullptr;
    return false;
  }

  gptimer_alarm_config_t alarm = {};
  alarm.alarm_count = intervalUs;
  alarm.reload_count = 0;
  alarm.flags.auto_reload_on_alarm = true;
  if (gptimer_set_alarm_action(handle, &alarm) != ESP_OK)
  {
    gptimer_del_timer(handle);
    slots[_id].callback = nullptr;
    slots[_id].arg = nullptr;
    return false;
  }

  if (gptimer_enable(handle) != ESP_OK || gptimer_start(handle) != ESP_OK)
  {
    gptimer_disable(handle);
    gptimer_del_timer(handle);
    slots[_id].callback = nullptr;
    slots[_id].arg = nullptr;
    return false;
  }

  _handle = handle;
  _running = true;
  return true;
}

void HwTimer::end()
{
  if (!_running) return;

  gptimer_handle_t handle = static_cast<gptimer_handle_t>(_handle);
  if (handle)
  {
    gptimer_stop(handle);
    gptimer_disable(handle);
    gptimer_del_timer(handle);
    _handle = nullptr;
  }

  slots[_id].callback = nullptr;
  slots[_id].arg = nullptr;
  _running = false;
}

} // namespace Hal

#endif
