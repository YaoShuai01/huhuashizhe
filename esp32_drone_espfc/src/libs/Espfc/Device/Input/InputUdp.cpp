#include "Device/Input/InputUdp.hpp"

#if defined(ESPFC_UDP_RX)

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <driver/ledc.h>
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

namespace Espfc::Device::Input {

namespace {
constexpr uint16_t UDP_PORT = 8888;
constexpr const char* AP_SSID = "HuHuaShiZhe-Drone";
constexpr int AP_CHANNEL = 6;
constexpr int AP_MAX_CONN = 2; // phone + vision board

// water pump: GPIO18, 5kHz/8bit, same 6-level duty table as the old firmware
constexpr gpio_num_t PIN_SPRAY = GPIO_NUM_18;
constexpr ledc_timer_t SPRAY_TIMER = LEDC_TIMER_1;
constexpr ledc_channel_t SPRAY_CHANNEL = LEDC_CHANNEL_4;
const uint8_t SPRAY_DUTY[7] = {0, 115, 140, 166, 191, 224, 255};

const char* PAGE_HEAD =
    "<!doctype html><html><head><meta charset='utf-8'>"
    "<meta http-equiv='refresh' content='0.5'>"
    "<meta name='viewport' content='width=device-width,initial-scale=1'>"
    "<style>body{font-family:sans-serif;background:#111;color:#eee;text-align:center;padding:12px}"
    "a{display:block;margin:10px;padding:16px;background:#2a7;color:#fff;text-decoration:none;border-radius:8px;font-size:19px}"
    "a.stop{background:#a33}</style></head><body>"
    "<h2>护花使者 姿态 / 电机测试</h2>"
    "<p style='color:#f66;font-size:18px'>必须先拆掉全部螺旋桨！</p>";

const char* PAGE_BUTTONS =
    "<p>点按钮自动强制上锁，电机中低速（约40%）转 3 秒</p>"
    "<a href='/m1'>电机1 后右 (GPIO21)</a>"
    "<a href='/m2'>电机2 前右 (GPIO1)</a>"
    "<a href='/m3'>电机3 后左 (GPIO12)</a>"
    "<a href='/m4'>电机4 前左 (GPIO4)</a>"
    "<a class='stop' href='/stop'>全部停止</a>"
    "<p>测完请到 APP 点“上锁”再“解锁”恢复</p></body></html>";

// Bench-test signs: flip any of these if a stick moves the wrong way.
// App left stick up = forward, so Betaflight pitch must go negative.
constexpr int ROLL_SIGN = 1;
constexpr int PITCH_SIGN = -1;
constexpr int YAW_SIGN = 1;
} // namespace

int InputUdp::begin(void)
{
  ledc_timer_config_t sprayTimer = {};
  sprayTimer.speed_mode = LEDC_LOW_SPEED_MODE;
  sprayTimer.duty_resolution = LEDC_TIMER_8_BIT;
  sprayTimer.timer_num = SPRAY_TIMER;
  sprayTimer.freq_hz = 5000;
  sprayTimer.clk_cfg = LEDC_AUTO_CLK;
  ledc_timer_config(&sprayTimer);

  ledc_channel_config_t sprayChannel = {};
  sprayChannel.gpio_num = PIN_SPRAY;
  sprayChannel.speed_mode = LEDC_LOW_SPEED_MODE;
  sprayChannel.channel = SPRAY_CHANNEL;
  sprayChannel.timer_sel = SPRAY_TIMER;
  sprayChannel.duty = 0;
  sprayChannel.hpoint = 0;
  sprayChannel.intr_type = LEDC_INTR_DISABLE;
  ledc_channel_config(&sprayChannel);

  WiFi.persistent(false);
  WiFi.mode(WIFI_AP);
  WiFi.setSleep(false);
  const bool ap = WiFi.softAP(AP_SSID, nullptr, AP_CHANNEL, false, AP_MAX_CONN);

  BaseType_t ret = xTaskCreatePinnedToCore(taskEntry, "udp_rc", 8192, this, 1, nullptr, 0);
  return (ap && ret == pdPASS) ? 1 : 0;
}

void InputUdp::taskEntry(void* arg)
{
  static_cast<InputUdp*>(arg)->taskLoop();
  vTaskDelete(nullptr);
}

void InputUdp::taskLoop()
{
  WiFiUDP udp;
  udp.begin(UDP_PORT);

  WiFiServer web(80);
  web.begin();

  char buf[256];
  for (;;)
  {
    const uint32_t now = millis();
    const int size = udp.parsePacket();
    if (size > 0)
    {
      const int len = udp.read(buf, sizeof(buf) - 1);
      if (len > 0)
      {
        buf[len] = 0;
        parse(buf, (size_t)len);
        _lastPacketMs = now;
        _packets++;
        _newFrame = true;
        _linked = true;
      }
    }

    WiFiClient client = web.available();
    if (client)
    {
      const String req = client.readStringUntil('\n');
      if (req.indexOf("/m1") >= 0) { _motorTest = 1; _motorTestUntil = now + 3000; _disarmLatch = true; }
      else if (req.indexOf("/m2") >= 0) { _motorTest = 2; _motorTestUntil = now + 3000; _disarmLatch = true; }
      else if (req.indexOf("/m3") >= 0) { _motorTest = 3; _motorTestUntil = now + 3000; _disarmLatch = true; }
      else if (req.indexOf("/m4") >= 0) { _motorTest = 4; _motorTestUntil = now + 3000; _disarmLatch = true; }
      else if (req.indexOf("/stop") >= 0) { _motorTest = 0; }
      client.print("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n");
      client.print(PAGE_HEAD);
      const auto& e = _model.state.attitude.euler;
      client.print("<p style='font-size:20px;line-height:1.6'>横滚 ");
      client.print(e[AXIS_ROLL] * 57.2958f, 1);
      client.print("°<br>俯仰 ");
      client.print(e[AXIS_PITCH] * 57.2958f, 1);
      client.print("°<br>航向 ");
      client.print(e[AXIS_YAW] * 57.2958f, 1);
      client.print("°</p><p>解锁=");
      client.print(_model.isModeActive(MODE_ARMED) ? 1 : 0);
      client.print(" 油门=");
      client.print((int)_throttle);
      client.print("us</p>");
      client.print(PAGE_BUTTONS);
      client.stop();
    }

    tick(now);
    vTaskDelay(pdMS_TO_TICKS(5));
  }
}

void InputUdp::parse(const char* buf, size_t len)
{
  char cmd[256];
  const size_t n = std::min(len, sizeof(cmd) - 1);
  memcpy(cmd, buf, n);
  cmd[n] = 0;

  char* save = nullptr;
  char* token = strtok_r(cmd, ";", &save);
  while (token)
  {
    while (*token == ' ' || *token == '\r' || *token == '\n' || *token == '\t') token++;
    char* colon = strchr(token, ':');
    if (colon)
    {
      *colon = 0;
      const char* key = token;
      const int v = atoi(colon + 1);

      if (strcmp(key, "ARM") == 0)
      {
        _armCmd = v != 0;
        if (!_armCmd) _disarmLatch = false;
      }
      else if (strcmp(key, "PIT") == 0)
      {
        _appPitch = std::clamp(v, -100, 100);
      }
      else if (strcmp(key, "ROL") == 0)
      {
        _appRoll = std::clamp(v, -100, 100);
      }
      else if (strcmp(key, "THR") == 0)
      {
        // Vertical throttle slider: 0..100 percent, mapped directly to 1000..2000us.
        _appThrottle = std::clamp(v, 0, 100);
      }
      else if (strcmp(key, "YAW") == 0)
      {
        _appYaw = std::clamp(v, -100, 100);
      }
      else if (strcmp(key, "SPR") == 0)
      {
        _sprayLevel = std::clamp(v, 0, 6);
      }
      else if (strcmp(key, "MOTOR") == 0)
      {
        _motorTest = std::clamp(v, 0, 4);
        _motorTestUntil = millis() + 3000;
        if (_motorTest > 0) _disarmLatch = true;
      }
      else if (strcmp(key, "LAND") == 0 && v != 0)
      {
        // Emergency disarm; there is no automatic takeoff anymore.
        _disarmLatch = true;
      }
    }
    token = strtok_r(nullptr, ";", &save);
  }
}

void InputUdp::linkLost()
{
  _linked = false;
  _disarmLatch = true;
  _throttle = THROTTLE_MIN;
  _appRoll = _appPitch = _appThrottle = _appYaw = 0;
  _sprayLevel = 0;
}

void InputUdp::applySpray()
{
  const bool safe = _armCmd && !_disarmLatch && _linked;
  const uint8_t duty = safe ? SPRAY_DUTY[_sprayLevel & 0x07] : 0;
  ledc_set_duty(LEDC_LOW_SPEED_MODE, SPRAY_CHANNEL, duty);
  ledc_update_duty(LEDC_LOW_SPEED_MODE, SPRAY_CHANNEL);
}

// Web/UDP motor test: only allowed while the FC is disarmed. One motor at a
// time at 1100us (about 10% throttle) for 3 seconds.
void InputUdp::applyMotorTest(uint32_t now)
{
  // While still armed, keep the pending test but force all outputs low. The
  // disarm latch set by the web handler will make the FC disarm, then the
  // test applies on the next tick.
  if (_model.isModeActive(MODE_ARMED))
  {
    for (size_t i = 0; i < 4; i++) _model.state.output.disarmed[i] = 1000;
    return;
  }

  if (_motorTest <= 0 || now > _motorTestUntil)
  {
    if (_motorTest > 0 && now > _motorTestUntil) _motorTest = 0;
    for (size_t i = 0; i < 4; i++) _model.state.output.disarmed[i] = 1000;
    return;
  }

  for (size_t i = 0; i < 4; i++)
  {
    _model.state.output.disarmed[i] = ((int)i == (_motorTest - 1)) ? 1400 : 1000;
  }
}

void InputUdp::publishChannels()
{
  const int roll = std::clamp(1500 + ROLL_SIGN * _appRoll * 5, 1000, 2000);
  const int pitch = std::clamp(1500 + PITCH_SIGN * _appPitch * 5, 1000, 2000);
  const int yaw = std::clamp(1500 + YAW_SIGN * _appYaw * 5, 1000, 2000);

  _channels[0] = (uint16_t)roll;
  _channels[1] = (uint16_t)pitch;
  _channels[2] = _throttle;
  _channels[3] = (uint16_t)yaw;
  _channels[4] = (_armCmd && !_disarmLatch) ? ARM_ON : ARM_OFF;
  _channels[5] = ANGLE_ON;
}

void InputUdp::tick(uint32_t now)
{
  applyMotorTest(now);

  if (_packets == 0 || (now - _lastPacketMs) > LINK_TIMEOUT_MS)
  {
    if (_linked) linkLost();
    _throttle = THROTTLE_MIN;
    _channels[2] = THROTTLE_MIN;
    _channels[4] = ARM_OFF;
    applySpray();
    return;
  }

  if (!_armCmd || _disarmLatch)
  {
    _throttle = THROTTLE_MIN;
    if (!_armCmd) _disarmLatch = false;
    publishChannels();
    applySpray();
    return;
  }

  // Keep throttle at 1000 until the FC has actually armed (gyro calibration and
  // arming checks), then follow the vertical slider directly.
  if (!_model.isModeActive(MODE_ARMED))
  {
    _throttle = THROTTLE_MIN;
    publishChannels();
    applySpray();
    return;
  }

  _throttle = (uint16_t)(THROTTLE_MIN + std::clamp(_appThrottle, 0, 100) * 10);
  publishChannels();
  applySpray();
}

InputStatus InputUdp::update()
{
  const uint32_t now = millis();
  if (_packets == 0 || (now - _lastPacketMs) > LINK_TIMEOUT_MS)
  {
    return Espfc::INPUT_LOST;
  }
  if (_newFrame)
  {
    _newFrame = false;
    return Espfc::INPUT_RECEIVED;
  }
  return Espfc::INPUT_IDLE;
}

uint16_t InputUdp::get(uint8_t i) const
{
  return i < CHANNELS ? _channels[i] : 1500;
}

void InputUdp::get(uint16_t* data, size_t len) const
{
  for (size_t i = 0; i < len && i < CHANNELS; i++)
  {
    data[i] = _channels[i];
  }
}

size_t InputUdp::getChannelCount() const
{
  return CHANNELS;
}

bool InputUdp::needAverage() const
{
  return false;
}

} // namespace Espfc::Device::Input

#endif
