#include "EscDriverEsp32.hpp"

#if defined(ESP32) && !defined(ESP32C3)

#include <algorithm>
#include <driver/ledc.h>

EscDriverEsp32::EscDriverEsp32() {}

uint32_t EscDriverEsp32::pulseToDuty(int pulse) const
{
  if (pulse < 0) pulse = 0;
  if (pulse > 2500) pulse = 2500;
  const uint64_t duty = (uint64_t)pulse * (uint64_t)_rate * (uint64_t)(1u << DUTY_BITS) / 1000000ULL;
  return (uint32_t)std::min<uint64_t>(duty, DUTY_MAX);
}

int EscDriverEsp32::begin(const EscConfig& conf)
{
  _timer = conf.timer;
  _rate = std::clamp(conf.rate, 50, 480);

  ledc_timer_config_t timer = {};
  timer.speed_mode = LEDC_LOW_SPEED_MODE;
  timer.duty_resolution = (ledc_timer_bit_t)DUTY_BITS;
  timer.timer_num = (ledc_timer_t)_timer;
  timer.freq_hz = (uint32_t)_rate;
  timer.clk_cfg = LEDC_AUTO_CLK;

  return ledc_timer_config(&timer) == ESP_OK ? 1 : 0;
}

void EscDriverEsp32::end()
{
  for (size_t i = 0; i < CHANNELS; i++)
  {
    if (!_channel[i].configured) continue;
    ledc_stop(LEDC_LOW_SPEED_MODE, (ledc_channel_t)i, 0);
    _channel[i].configured = false;
    _channel[i].pin = -1;
  }
}

int EscDriverEsp32::attach(size_t channel, int pin, int pulse)
{
  if (channel >= CHANNELS || pin < 0) return 0;

  ledc_channel_config_t conf = {};
  conf.gpio_num = pin;
  conf.speed_mode = LEDC_LOW_SPEED_MODE;
  conf.channel = (ledc_channel_t)channel;
  conf.timer_sel = (ledc_timer_t)_timer;
  conf.duty = pulseToDuty(pulse);
  conf.hpoint = 0;
  conf.intr_type = LEDC_INTR_DISABLE;

  if (ledc_channel_config(&conf) != ESP_OK) return 0;

  _channel[channel].pin = pin;
  _channel[channel].pulse = pulse;
  _channel[channel].configured = true;
  return 1;
}

int EscDriverEsp32::write(size_t channel, int pulse)
{
  if (channel >= CHANNELS || !_channel[channel].configured) return 0;
  _channel[channel].pulse = pulse;
  return 1;
}

void EscDriverEsp32::apply()
{
  for (size_t i = 0; i < CHANNELS; i++)
  {
    if (!_channel[i].configured) continue;
    ledc_set_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)i, pulseToDuty(_channel[i].pulse));
    ledc_update_duty(LEDC_LOW_SPEED_MODE, (ledc_channel_t)i);
  }
}

int EscDriverEsp32::pin(size_t channel) const
{
  return channel < CHANNELS ? _channel[channel].pin : -1;
}

uint32_t EscDriverEsp32::telemetry(size_t channel) const
{
  (void)channel;
  return 0;
}

#endif
