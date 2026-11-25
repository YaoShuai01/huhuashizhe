#include "Device/Input/InputUdp.hpp"

#if defined(ESPFC_UDP_RX)

#include <Arduino.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiUdp.h>
#include <esp_wifi.h>
#include <driver/ledc.h>
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

#include "Control/Controller.hpp"
#include "Utils/Math.hpp"

namespace Espfc::Device::Input {

namespace {
constexpr uint16_t UDP_PORT = 8888;
constexpr const char* AP_SSID = "HuHuaShiZhe-Drone";
constexpr int AP_CHANNEL = 6;
// Android may reconnect with a randomized MAC; stale entries hold slots until
// timeout, so keep enough headroom to avoid "can see but cannot join".
constexpr int AP_MAX_CONN = 8; // phone + vision board + retries

// water pump: GPIO18, 5kHz/8bit, same 6-level duty table as the old firmware
constexpr gpio_num_t PIN_SPRAY = GPIO_NUM_18;
constexpr ledc_timer_t SPRAY_TIMER = LEDC_TIMER_1;
constexpr ledc_channel_t SPRAY_CHANNEL = LEDC_CHANNEL_4;
const uint8_t SPRAY_DUTY[7] = {0, 115, 140, 166, 191, 224, 255};

// 飞行微调：单位 0.1（水平为 0.1 度，旋转为 0.1 度/秒），范围 ±100，存 NVS 永久保存
constexpr int TRIM_LIMIT = 100;

int currentTrim(int axis)
{
  return (int)lroundf(Utils::toDeg(Control::Controller::getTrim(axis)) * 10.0f);
}

void saveTrim(int rollTenths, int pitchTenths, int yawTenths)
{
  rollTenths = std::clamp(rollTenths, -TRIM_LIMIT, TRIM_LIMIT);
  pitchTenths = std::clamp(pitchTenths, -TRIM_LIMIT, TRIM_LIMIT);
  yawTenths = std::clamp(yawTenths, -TRIM_LIMIT, TRIM_LIMIT);

  Preferences prefs;
  prefs.begin("hhs", false);
  prefs.putInt("trim_r", rollTenths);
  prefs.putInt("trim_p", pitchTenths);
  prefs.putInt("trim_y", yawTenths);
  prefs.end();

  Control::Controller::setTrim(AXIS_ROLL, Utils::toRad(rollTenths * 0.1f));
  Control::Controller::setTrim(AXIS_PITCH, Utils::toRad(pitchTenths * 0.1f));
  Control::Controller::setTrim(AXIS_YAW, Utils::toRad(yawTenths * 0.1f));
}

int queryInt(const String& req, const char* key, int def)
{
  const String k = String("?") + key + "=";
  const String k2 = String("&") + key + "=";
  int idx = req.indexOf(k);
  int skip = k.length();
  if (idx < 0)
  {
    idx = req.indexOf(k2);
    skip = k2.length();
  }
  if (idx < 0) return def;
  return atoi(req.c_str() + idx + skip);
}

String queryStr(const String& req, const char* key)
{
  const String k = String("?") + key + "=";
  const String k2 = String("&") + key + "=";
  int idx = req.indexOf(k);
  int skip = k.length();
  if (idx < 0)
  {
    idx = req.indexOf(k2);
    skip = k2.length();
  }
  if (idx < 0) return "";
  const int start = idx + skip;
  int end = req.indexOf('&', start);
  if (end < 0) end = req.indexOf(' ', start);
  if (end < 0) end = req.length();
  return req.substring(start, end);
}

// 只允许安全字符，避免路径穿越
String sanitizeName(const String& s)
{
  String out;
  for (size_t i = 0; i < s.length() && out.length() < 40; i++)
  {
    const char c = s[i];
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.' ||
        c == '-')
      out += c;
  }
  return out;
}

const char* PAGE_HEAD =
    "<!doctype html><html><head><meta charset='utf-8'>"
    "<meta http-equiv='refresh' content='1'>"
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
    "<p>测完请到 APP 点“上锁”再“解锁”恢复</p>"
    "<p style='margin-top:16px'>电调行程校准：</p>"
    "<a class='stop' href='/cal'>电调校准（下次上电）</a>"
    "<p style='font-size:13px;color:#aaa'>点完后断开电池再重新接上；上电后电调先响满油门，3 秒后自动降到最低。必须先拆桨！</p>"
    "</body></html>";

// Bench-test signs: flip any of these if a stick moves the wrong way.
// App left stick up = forward, so Betaflight pitch must go negative.
constexpr int ROLL_SIGN = 1;
constexpr int PITCH_SIGN = 1;
constexpr int YAW_SIGN = 1;
} // namespace

int InputUdp::begin(void)
{
  // Optional ESC throttle-range calibration on the next power-up: hold 2000us
  // for 3s, then drop to 1000us. Props must be removed.
  Preferences prefs;
  prefs.begin("hhs", false);
  const bool escCal = prefs.getBool("esc_cal", false);
  if (escCal)
  {
    prefs.putBool("esc_cal", false);
    prefs.end();
    auto* motor = _model.state.mixer.escMotor;
    if (motor)
    {
      for (int i = 0; i < 4; i++) motor->write(i, 2000);
      motor->apply();
      vTaskDelay(pdMS_TO_TICKS(3000));
      for (int i = 0; i < 4; i++) motor->write(i, 1000);
      motor->apply();
      vTaskDelay(pdMS_TO_TICKS(500));
    }
  }
  else
  {
    prefs.end();
  }

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

  // DTIM=1：手机省电模式下每个 beacon（100ms）都能取走缓存的下行包。
  // 默认 DTIM=3 时下行要等 300ms，TCP 吞吐会被压到 1Mbps 以下，图传必然丢段。
  {
    wifi_config_t apcfg = {};
    if (esp_wifi_get_config(WIFI_IF_AP, &apcfg) == ESP_OK)
    {
      apcfg.ap.dtim_period = 1;
      apcfg.ap.beacon_interval = 100;
      esp_wifi_set_config(WIFI_IF_AP, &apcfg);
      printf("[WIFI] ap dtim=%d beacon=%dms\n", (int)apcfg.ap.dtim_period, (int)apcfg.ap.beacon_interval);
      fflush(stdout);
    }
  }

  // 图传下行实测只有 2.2Mbps（191 pkt/s），像是 AP 一直在用 11b/低速率发。
  // 强制只用 11n 并固定 MCS5（57.8Mbps，-40dBm 下余量足够），把空口下限抬起来。
  {
    const esp_err_t pr = esp_wifi_set_protocol(WIFI_IF_AP, WIFI_PROTOCOL_11N);
    const esp_err_t rr = esp_wifi_config_80211_tx_rate(WIFI_IF_AP, WIFI_PHY_RATE_MCS5_LGI);
    printf("[WIFI] ap 11n=%d mcs5=%d\n", (int)pr, (int)rr);
    fflush(stdout);
  }

  // 从 NVS 恢复飞行微调（水平 0.1 度，旋转 0.1 度/秒，永久保存）
  {
    Preferences prefs;
    prefs.begin("hhs", true);
    const int32_t tr = prefs.getInt("trim_r", 0);
    const int32_t tp = prefs.getInt("trim_p", 0);
    const int32_t ty = prefs.getInt("trim_y", 0);
    prefs.end();
    Control::Controller::setTrim(AXIS_ROLL, Utils::toRad(tr * 0.1f));
    Control::Controller::setTrim(AXIS_PITCH, Utils::toRad(tp * 0.1f));
    Control::Controller::setTrim(AXIS_YAW, Utils::toRad(ty * 0.1f));
  }

  // 偏航修正方向：桨/电机全部反向安装的机架需要翻转，存 NVS 永久生效
  {
    Preferences prefs;
    prefs.begin("hhs", true);
    // Key renamed to v2 so a previously stored (wrong) "开" does not override
    // the corrected default. Correct value for this airframe is OFF.
    _model.config.mixer.yawReverse = prefs.getBool("yawrev2", false);
    prefs.end();
  }

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
      // Browsers open speculative connections that send nothing. Without a short
      // timeout readStringUntil() blocks up to 1s per socket and starves the UDP
      // RC loop (page freezes, link drops). 50ms is plenty for a local GET line.
      client.setTimeout(50);
      const String req = client.readStringUntil('\n');
      if (req.indexOf("GET ") < 0)
      {
        client.stop();
        tick(now);
        vTaskDelay(pdMS_TO_TICKS(2));
        continue;
      }

      // ---- JSON API（APP 使用）----
      if (req.indexOf("/api/") >= 0)
      {
        String body;
        int code = 200;
        String ctype = "application/json";

        if (req.indexOf("/api/state") >= 0)
        {
          const auto& g = _model.state.gyro.adc;
          const auto& e = _model.state.attitude.euler;
          const auto& gps = _model.state.gps;
          const int32_t lat = gps.location.raw.lat;
          const int32_t lon = gps.location.raw.lon;
          body = "{\"ok\":1";
          body += ",\"armed\":" + String(_model.isModeActive(MODE_ARMED) ? 1 : 0);
          body += ",\"yawrev\":" + String(_model.config.mixer.yawReverse ? 1 : 0);
          body += ",\"thr\":" + String((int)_throttle);
          body += ",\"gyro\":[" + String(g[AXIS_ROLL], 1) + "," + String(g[AXIS_PITCH], 1) + "," +
                  String(g[AXIS_YAW], 1) + "]";
          body += ",\"angle\":[" + String(e[AXIS_ROLL] * 57.2958f, 1) + "," +
                  String(e[AXIS_PITCH] * 57.2958f, 1) + "," + String(e[AXIS_YAW] * 57.2958f, 1) + "]";
          body += ",\"mag\":[" + String(_model.state.mag.raw.x) + "," +
                  String(_model.state.mag.raw.y) + "," + String(_model.state.mag.raw.z) + "]";
          body += ",\"motors\":[" + String(_model.state.output.us[0]) + "," +
                  String(_model.state.output.us[1]) + "," + String(_model.state.output.us[2]) + "," +
                  String(_model.state.output.us[3]) + "]";
          body += ",\"ch\":[" + String((int)_model.state.input.us[AXIS_ROLL]) + "," +
                  String((int)_model.state.input.us[AXIS_PITCH]) + "," +
                  String((int)_model.state.input.us[AXIS_THRUST]) + "," +
                  String((int)_model.state.input.us[AXIS_YAW]) + "]";
          body += ",\"dev\":{\"gyro\":" + String(_model.state.gyro.present ? 1 : 0) +
                  ",\"accel\":" + String(_model.state.accel.present ? 1 : 0) +
                  ",\"mag\":" + String(_model.state.mag.present ? 1 : 0) +
                  ",\"baro\":" + String(_model.state.baro.present ? 1 : 0) + "}";
          body += ",\"baro\":{\"alt\":" + String(_model.state.baro.altitudeGround, 2) +
                  ",\"vario\":" + String(_model.state.baro.vario, 2) +
                  ",\"press\":" + String(_model.state.baro.pressure * 0.01f, 1) + "}";
          body += ",\"gps\":{\"present\":" + String(gps.present ? 1 : 0) +
                  ",\"fix\":" + String(gps.fix ? 1 : 0) +
                  ",\"type\":" + String(gps.fixType) +
                  ",\"sats\":" + String(gps.numSats) +
                  ",\"lat\":" + String(lat * 1e-7, 7) +
                  ",\"lon\":" + String(lon * 1e-7, 7) +
                  ",\"alt\":" + String(gps.location.raw.height * 0.001f, 1) +
                  ",\"spd\":" + String(gps.velocity.raw.groundSpeed * 0.001f, 2) +
                  ",\"cog\":" + String(gps.velocity.raw.heading * 1e-5f, 1) + "}";
          body += "}";
        }
        else if (req.indexOf("/api/yawrev") >= 0)
        {
          // Return HTML (auto back to the status page) so the link button is
          // actually usable from a phone browser instead of a raw JSON page.
          ctype = "text/html; charset=utf-8";
          if (_model.isModeActive(MODE_ARMED))
          {
            code = 409;
            body = "<html><body style='font-size:22px;background:#111;color:#eee'>"
                   "请先在 APP 点「上锁」，再切换偏航反向"
                   "<meta http-equiv='refresh' content='3;url=/'></body></html>";
          }
          else
          {
            const int on = std::clamp(queryInt(req, "on", _model.config.mixer.yawReverse ? 1 : 0), 0, 1);
            _model.config.mixer.yawReverse = on != 0;
            Preferences prefs;
            prefs.begin("hhs", false);
            prefs.putBool("yawrev2", on != 0);
            prefs.end();
            body = "<html><body style='font-size:22px;background:#111;color:#eee'>偏航反向已设为";
            body += on ? "开" : "关";
            body += "<meta http-equiv='refresh' content='1;url=/'></body></html>";
          }
        }
        else if (req.indexOf("/api/gyrocal") >= 0)
        {
          if (_model.isModeActive(MODE_ARMED))
          {
            code = 409;
            body = "{\"ok\":0,\"err\":\"armed\"}";
          }
          else if (_model.calibrationActive())
          {
            code = 409;
            body = "{\"ok\":0,\"err\":\"busy\"}";
          }
          else
          {
            _model.calibrateGyroBias();
            body = "{\"ok\":1,\"ms\":2000}";
          }
        }
        else if (req.indexOf("/api/accelcal") >= 0)
        {
          // 加速度计水平校准：飞机必须静止且放平，约 2 秒采样后写入 NVS
          if (_model.isModeActive(MODE_ARMED))
          {
            code = 409;
            body = "{\"ok\":0,\"err\":\"armed\"}";
          }
          else if (_model.calibrationActive())
          {
            code = 409;
            body = "{\"ok\":0,\"err\":\"busy\"}";
          }
          else
          {
            _model.calibrateAccel();
            body = "{\"ok\":1,\"ms\":2000}";
          }
        }
        else if (req.indexOf("/api/trimget") >= 0)
        {
          body = "{\"ok\":1,\"r\":" + String(currentTrim(AXIS_ROLL)) +
                 ",\"p\":" + String(currentTrim(AXIS_PITCH)) +
                 ",\"y\":" + String(currentTrim(AXIS_YAW)) + "}";
        }
        else if (req.indexOf("/api/trimclear") >= 0)
        {
          saveTrim(0, 0, 0);
          body = "{\"ok\":1,\"r\":0,\"p\":0,\"y\":0}";
        }
        else if (req.indexOf("/api/trim") >= 0)
        {
          const int r = std::clamp(queryInt(req, "r", currentTrim(AXIS_ROLL)), -TRIM_LIMIT, TRIM_LIMIT);
          const int p = std::clamp(queryInt(req, "p", currentTrim(AXIS_PITCH)), -TRIM_LIMIT, TRIM_LIMIT);
          const int y = std::clamp(queryInt(req, "y", currentTrim(AXIS_YAW)), -TRIM_LIMIT, TRIM_LIMIT);
          saveTrim(r, p, y);
          body = "{\"ok\":1,\"r\":" + String(r) + ",\"p\":" + String(p) +
                 ",\"y\":" + String(y) + "}";
        }
        else if (req.indexOf("/api/log") >= 0)
        {
          // 飞行日志下载：仅在未解锁时允许，避免下载大文件阻塞遥控
          if (_model.isModeActive(MODE_ARMED))
          {
            code = 409;
            body = "{\"ok\":0,\"err\":\"armed\"}";
          }
          else
          {
            String name = sanitizeName(queryStr(req, "f"));
            if (name.length() == 0) name = "flight_000.csv";
            if (name[0] != '/') name = "/" + name;
            if (!LittleFS.exists(name))
            {
              code = 404;
              body = "{\"ok\":0,\"err\":\"nofile\"}";
            }
            else
            {
              File f = LittleFS.open(name, FILE_READ);
              client.print("HTTP/1.1 200 OK\r\nContent-Type: text/csv; charset=utf-8\r\n");
              client.print("Content-Disposition: attachment; filename=\"" + name.substring(1) + "\"\r\n");
              client.print("Content-Length: " + String((unsigned)f.size()) + "\r\nConnection: close\r\n\r\n");
              uint8_t chunk[512];
              while (f.available())
              {
                const size_t rd = f.read(chunk, sizeof(chunk));
                if (!rd) break;
                client.write(chunk, rd);
                tick(now); // 下载期间保持通道/状态更新
              }
              f.close();
              client.stop();
              vTaskDelay(pdMS_TO_TICKS(5));
              continue;
            }
          }
        }
        else
        {
          code = 404;
          body = "{\"ok\":0,\"err\":\"notfound\"}";
        }

        client.print("HTTP/1.1 " + String(code) + " OK\r\nContent-Type: " + ctype +
                     "\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n");
        client.print(body);
        client.stop();
        tick(now);
        vTaskDelay(pdMS_TO_TICKS(5));
        continue;
      }

      if (req.indexOf("/logs") >= 0)
      {
        client.print("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n");
        client.print("<!doctype html><html><head><meta charset='utf-8'>");
        client.print("<meta name='viewport' content='width=device-width,initial-scale=1'>");
        client.print("<style>body{font-family:sans-serif;background:#111;color:#eee;padding:14px}");
        client.print("a{display:block;margin:8px 0;padding:14px;background:#2a7;color:#fff;");
        client.print("text-decoration:none;border-radius:8px;font-size:17px}a.back{background:#444}");
        client.print("</style></head><body><h2>飞行日志</h2>");
        client.print("<p>解锁后自动记录（50Hz）。点文件名下载 CSV。</p>");
        File root = LittleFS.open("/");
        int count = 0;
        File f = root.openNextFile();
        while (f)
        {
          const String n = String(f.name());
          if (!f.isDirectory() && n.endsWith(".csv"))
          {
            String base = n;
            if (base.startsWith("/")) base = base.substring(1);
            client.print("<a href='/api/log?f=" + base + "'>" + base + " (" + String((unsigned)f.size() / 1024) +
                         " KB)</a>");
            count++;
          }
          f = root.openNextFile();
        }
        root.close();
        if (count == 0) client.print("<p>还没有日志：需要解锁一次才会开始记录。</p>");
        client.print("<p><a class='back' href='/'>返回状态页</a></p></body></html>");
        client.stop();
        tick(now);
        vTaskDelay(pdMS_TO_TICKS(5));
        continue;
      }

      if (req.indexOf("/m1") >= 0) { _motorTest = 1; _motorTestUntil = now + 3000; _disarmLatch = true; }
      else if (req.indexOf("/m2") >= 0) { _motorTest = 2; _motorTestUntil = now + 3000; _disarmLatch = true; }
      else if (req.indexOf("/m3") >= 0) { _motorTest = 3; _motorTestUntil = now + 3000; _disarmLatch = true; }
      else if (req.indexOf("/m4") >= 0) { _motorTest = 4; _motorTestUntil = now + 3000; _disarmLatch = true; }
      else if (req.indexOf("/stop") >= 0) { _motorTest = 0; }
      else if (req.indexOf("/cal") >= 0)
      {
        Preferences calPrefs;
        calPrefs.begin("hhs", false);
        calPrefs.putBool("esc_cal", true);
        calPrefs.end();
      }
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
      client.print("<p style='font-size:16px'>陀螺°/s 横滚 ");
      client.print(_model.state.gyro.adc[AXIS_ROLL] * 57.2958f, 1);
      client.print(" 俯仰 ");
      client.print(_model.state.gyro.adc[AXIS_PITCH] * 57.2958f, 1);
      client.print(" 偏航 ");
      client.print(_model.state.gyro.adc[AXIS_YAW] * 57.2958f, 1);
      client.print("</p>");
      client.print("<p style='font-size:16px'>磁力计 ");
      if (_model.state.mag.present)
      {
        client.print((int)_model.state.mag.raw.x);
        client.print(" / ");
        client.print((int)_model.state.mag.raw.y);
        client.print(" / ");
        client.print((int)_model.state.mag.raw.z);
      }
      else
      {
        client.print("未检测到");
      }
      client.print("</p>");
      client.print("<p style='font-size:16px'>电机 ");
      for (int i = 0; i < 4; i++)
      {
        client.print(_model.state.output.us[i]);
        client.print(" ");
      }
      client.print("</p>");
      client.print("<p style='font-size:16px'>气压计 ");
      if (_model.state.baro.present)
      {
        client.print(_model.state.baro.altitudeGround, 1);
        client.print("m 爬升 ");
        client.print(_model.state.baro.vario, 2);
        client.print("m/s ");
        client.print(_model.state.baro.pressure * 0.01f, 1);
        client.print("hPa");
      }
      else
      {
        client.print("未检测到");
      }
      client.print("</p>");
      client.print("<p style='font-size:16px'>GPS ");
      if (_model.state.gps.present)
      {
        client.print(_model.state.gps.fix ? "已定位" : "搜星中");
        client.print(" 卫星 ");
        client.print(_model.state.gps.numSats);
        if (_model.state.gps.fix)
        {
          client.print(" 经纬 ");
          client.print(_model.state.gps.location.raw.lat * 1e-7f, 6);
          client.print(", ");
          client.print(_model.state.gps.location.raw.lon * 1e-7f, 6);
        }
      }
      else
      {
        client.print("未检测到");
      }
      client.print("</p>");
      client.print("<p>链路 收 ");
      client.print((uint32_t)_packets);
      client.print(" / 丢 ");
      client.print((uint32_t)_lostCount);
      client.print(" / ");
      if (_packets == 0)
      {
        client.print("无包（APP 未连接）");
      }
      else
      {
        client.print("年龄 ");
        client.print((uint32_t)(now - _lastPacketMs));
        client.print("ms");
      }
      client.print("</p>");
      client.print("<p>微调 横滚 ");
      client.print(currentTrim(AXIS_ROLL) * 0.1f, 1);
      client.print("° 俯仰 ");
      client.print(currentTrim(AXIS_PITCH) * 0.1f, 1);
      client.print("° 旋转 ");
      client.print(currentTrim(AXIS_YAW) * 0.1f, 1);
      client.print("°/s</p>");
      client.print("<p>偏航反向 ");
      client.print(_model.config.mixer.yawReverse ? "开" : "关");
      client.print("（原地自旋时切换试试，上锁后才能改）</p>");
      client.print("<a href='/api/yawrev?on=1'>偏航反向 开</a>");
      client.print("<a href='/api/yawrev?on=0'>偏航反向 关</a>");
      client.print("<a href='/api/gyrocal'>陀螺仪校准（静止时点）</a>");
      client.print("<a href='/api/accelcal'>加速度计水平校准（放平后点）</a>");
      client.print("<a class='stop' href='/api/trimclear'>清除微调</a>");
      client.print("<a href='/logs'>飞行日志下载</a>");
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
  _lostCount++;
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
    // A short WiFi stall cuts throttle but keeps the FC armed so the link can
    // recover without a full disarm. Only a long outage disarms.
    if ((now - _lastPacketMs) > DISARM_TIMEOUT_MS) _disarmLatch = true;
    _channels[4] = (_armCmd && !_disarmLatch) ? ARM_ON : ARM_OFF;
    applySpray();
    return;
  }
  if (!_linked) _linked = true;

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
