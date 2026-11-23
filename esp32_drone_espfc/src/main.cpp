#include <Arduino.h>
#include <HWCDC.h>
#include <LittleFS.h>
#include <WiFi.h>
#include <esp_partition.h>
#include <Espfc.hpp>
#include <Hal/FastCode.hpp>
#include <Hal/Platform.hpp>
#include <Hal/Task.hpp>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

// 板载 WS2812 全彩灯：DevKitC-1 v1.0 为 GPIO48；若板子是 v1.1（灯接 GPIO38）改这里
// 节奏：蓝色每 1.5 秒一次；绿色每 3 秒一次（3 秒周期：0ms 蓝 → 180ms 绿 → 1500ms 蓝）
#define STATUS_LED_PIN 48
#define STATUS_LED_CYCLE_MS 3000
#define STATUS_LED_PULSE_MS 120
#define STATUS_LED_GREEN_AT_MS 180
#define STATUS_LED_BLUE2_AT_MS 1500

#if defined(ESPFC_HAL_C_LINKAGE_ENTRY)
// esp8266 and pico expect C-style linkage
extern "C" void setup();
extern "C" void loop();
extern "C" void setup1();
extern "C" void loop1();
#endif

Espfc::Espfc espfc;

#if ESPFC_HAL_CORE_COUNT > 1
#if defined(ESPFC_HAL_FREE_RTOS)

// RTOS multicore, gyro loop is triggered by the hardware timer interrupt
using Hal::Task;

Task::Handle gyroTaskHandle = nullptr;

bool ISR_CODE_ATTR gyroTimerIsr(void* args)
{
  return Task::notifyFromIsr(gyroTaskHandle);
}

void gyroTask(void* pvParameters)
{
  gyroTaskHandle = Task::currentHandle();
  espfc.begin();
  printf("[ESPFC] gyro=%d accel=%d mag=%d baro=%d gps=%d rate=%dHz\n",
         (int)espfc.isGyroReady(), (int)espfc.isAccelReady(),
         (int)espfc.isMagReady(), (int)espfc.isBaroReady(),
         (int)espfc.isGpsReady(), espfc.gyroRate());
  fflush(stdout);
  bool timerOk = espfc.beginGyroTimer(gyroTimerIsr);
  if (!timerOk)
  {
    printf("[ESPFC] ERROR: gyro timer start failed\n");
    fflush(stdout);
  }
  while (true)
  {
    Task::waitNotify(); // wait for timer isr notification
    espfc.update(true);
  }
}

void pidTask(void* pvParameters)
{
  while (true)
  {
    // updateOther() returns 0 when the event queue is empty. Yield to the
    // core-0 idle task in that case so it can feed the task watchdog.
    if (!espfc.updateOther())
    {
      vTaskDelay(1);
    }
  }
}

// WiFi AP 连接事件日志：定位"能搜到但连不上/连上就断"的原因
static void wifiEvent(WiFiEvent_t event, WiFiEventInfo_t info)
{
  switch (event)
  {
    case ARDUINO_EVENT_WIFI_AP_START:
      printf("[WIFI] AP started, ip=%s\n", WiFi.softAPIP().toString().c_str());
      break;
    case ARDUINO_EVENT_WIFI_AP_STACONNECTED:
      printf("[WIFI] station connected\n");
      break;
    case ARDUINO_EVENT_WIFI_AP_STADISCONNECTED:
      printf("[WIFI] station disconnected, reason=%d\n", (int)info.wifi_ap_stadisconnected.reason);
      break;
    case ARDUINO_EVENT_WIFI_AP_STOP:
      printf("[WIFI] AP stopped\n");
      break;
    default:
      break;
  }
  fflush(stdout);
}

void setup()
{
  // Do NOT call disableCore0WDT() here: on Arduino core 3.x it only removes
  // the core-0 idle task from the task WDT, whose idle hook then logs
  // "esp_task_wdt_reset: task not found" every few milliseconds.
  WiFi.onEvent(wifiEvent);
  Serial.begin(115200);

  // 飞行日志文件系统：首次使用或分区表刚变更时需要格式化
  {
    // 打印实际分区表，确认 storage 分区是否真的写进了芯片
    esp_partition_iterator_t it = esp_partition_find(ESP_PARTITION_TYPE_ANY, ESP_PARTITION_SUBTYPE_ANY, NULL);
    for (; it != NULL; it = esp_partition_next(it))
    {
      const esp_partition_t* p = esp_partition_get(it);
      printf("[PART] %s type=%d sub=%d off=0x%X size=0x%X\n", p->label, (int)p->type, (int)p->subtype,
             (unsigned)p->address, (unsigned)p->size);
    }
    esp_partition_iterator_release(it);
    fflush(stdout);
  }

  if (!LittleFS.begin(false, "/littlefs", 10, "storage"))
  {
    printf("[LOG] LittleFS mount failed, formatting...\n");
    fflush(stdout);
    if (LittleFS.begin(true, "/littlefs", 10, "storage"))
    {
      printf("[LOG] formatted ok\n");
    }
    else
    {
      printf("[LOG] format failed, flight log disabled\n");
    }
    fflush(stdout);
  }
  printf("[LOG] fs total=%u used=%u\n", (unsigned)LittleFS.totalBytes(), (unsigned)LittleFS.usedBytes());
  fflush(stdout);

  espfc.load();
  Task::create(gyroTask, "gyroTask", 8192, nullptr, Task::Priority::High, 1);
  Task::create(pidTask, "pidTask", 8192, nullptr, Task::Priority::Low, 0);
  // Keep the Arduino loop task alive: it feeds the task watchdog. Deleting it
  // causes "esp_task_wdt_reset: task not found" and a boot loop on core 3.x.
}

// 飞行日志：解锁即开始记录，上锁时关闭文件；文件保存在 Flash，手机浏览器可下载
static File g_log;
static bool g_logOpen = false;
static uint32_t g_logFlush = 0;

static void flightLogTick(uint32_t now)
{
  const bool armed = espfc.isArmed();

  if (armed && !g_logOpen)
  {
    int idx = 0;
    char path[32];
    do
    {
      snprintf(path, sizeof(path), "/flight_%03d.csv", idx);
      idx++;
    } while (LittleFS.exists(path) && idx < 1000);

    g_log = LittleFS.open(path, FILE_WRITE);
    g_logOpen = (bool)g_log;
    if (g_logOpen)
    {
      g_log.print("ms,armed,gx,gy,gz,sx,sy,sz,ox,oy,oz,ir,ip,it,iy,m0,m1,m2,m3,alt,vario,sats\n");
      printf("[LOG] recording %s\n", path);
    }
    else
    {
      printf("[LOG] open %s failed\n", path);
    }
    fflush(stdout);
  }

  if (g_logOpen && armed)
  {
    char line[192];
    const int n = espfc.logFlight(now, line, sizeof(line));
    if (n > 0) g_log.print(line);
    if (now - g_logFlush >= 1000)
    {
      g_logFlush = now;
      g_log.flush();
    }
  }
  else if (g_logOpen)
  {
    g_log.flush();
    g_log.close();
    g_logOpen = false;
    printf("[LOG] closed, used=%u\n", (unsigned)LittleFS.usedBytes());
    fflush(stdout);
  }
}

// 全彩灯心跳：蓝 1.5 秒一次、绿 3 秒一次
enum StatusLedColor
{
  STATUS_LED_OFF,
  STATUS_LED_BLUE,
  STATUS_LED_GREEN,
};

// 串口日志导出：电脑发送 DUMP 回车，飞控把 Flash 里的 CSV 全部打印到 USB 串口
// 注意：本板 USBMode=hwcdc，USB 串口对象是 HWCDCSerial
#if defined(HWCDC_SERIAL_IS_DEFINED) && HWCDC_SERIAL_IS_DEFINED
#define HHS_USB HWCDCSerial
#else
#define HHS_USB Serial
#endif

static String g_serialCmd;

static void serialLogCommand()
{
  while (HHS_USB.available())
  {
    const char c = (char)HHS_USB.read();
    if (c == '\n')
    {
      g_serialCmd.trim();
      if (g_serialCmd == "DUMP" || g_serialCmd == "LIST")
      {
        File root = LittleFS.open("/");
        File f = root.openNextFile();
        while (f)
        {
          const String n = String(f.name());
          if (!f.isDirectory() && n.endsWith(".csv"))
          {
            printf("===FILE %s %u===\r\n", f.name(), (unsigned)f.size());
            fflush(stdout);
            if (g_serialCmd == "DUMP")
            {
              uint8_t buf[256];
              while (f.available())
              {
                const size_t rd = f.read(buf, sizeof(buf));
                if (!rd) break;
                HHS_USB.write(buf, rd);
              }
              printf("\r\n===END===\r\n");
            }
          }
          f = root.openNextFile();
        }
        root.close();
        printf("===DONE===\r\n");
        fflush(stdout);
      }
      g_serialCmd = "";
    }
    else if (c != '\r')
    {
      if (g_serialCmd.length() < 16) g_serialCmd += c;
    }
  }
}

void loop()
{
  static uint32_t cycleStart = 0;
  static StatusLedColor shown = STATUS_LED_OFF;

  uint32_t now = millis();
  uint32_t t = now - cycleStart;
  if (t >= STATUS_LED_CYCLE_MS)
  {
    cycleStart = now;
    t = 0;
  }

  StatusLedColor want = STATUS_LED_OFF;
  if (t < STATUS_LED_PULSE_MS ||
      (t >= STATUS_LED_BLUE2_AT_MS && t < STATUS_LED_BLUE2_AT_MS + STATUS_LED_PULSE_MS))
  {
    want = STATUS_LED_BLUE;
  }
  else if (t >= STATUS_LED_GREEN_AT_MS && t < STATUS_LED_GREEN_AT_MS + STATUS_LED_PULSE_MS)
  {
    want = STATUS_LED_GREEN;
  }

  if (want != shown)
  {
    if (want == STATUS_LED_BLUE)
      rgbLedWrite(STATUS_LED_PIN, 0, 0, 80);
    else if (want == STATUS_LED_GREEN)
      rgbLedWrite(STATUS_LED_PIN, 0, 80, 0);
    else
      rgbLedWrite(STATUS_LED_PIN, 0, 0, 0);
    shown = want;
  }

  // 调试期每 5 秒打印一次传感器状态，接 USB 串口即可看到气压计/GPS/磁力计数据
  static uint32_t lastStatus = 0;
  if (now - lastStatus >= 5000)
  {
    lastStatus = now;
    printf("[ESPFC] baro=%d press=%dPa alt=%dcm vario=%dcm/s gps=%d fix=%d sats=%d mag=%d/%d/%d wifi_sta=%d\n",
           (int)espfc.isBaroReady(), espfc.baroPressure(), espfc.baroAltitude10() * 10,
           espfc.baroVario100(),
           (int)espfc.isGpsReady(), (int)espfc.isGpsFix(), espfc.gpsSats(),
           espfc.magX(), espfc.magY(), espfc.magZ(),
           (int)WiFi.softAPgetStationNum());
    fflush(stdout);
  }
  // 偏航诊断：解锁后每 200ms 打印一次，用地面手拧机身即可判断方向是否正确
  static uint32_t lastYaw = 0;
  if (espfc.isArmed() && now - lastYaw >= 200)
  {
    lastYaw = now;
    printf("[YAW] gyro=%d sp=%d out=%d m=%d,%d,%d,%d\n",
           (int)espfc.gyroYawDeg(), (int)espfc.setpointYawDeg(),
           (int)(espfc.outputYaw() * 1000.f),
           espfc.motorUs(0), espfc.motorUs(1), espfc.motorUs(2), espfc.motorUs(3));
    fflush(stdout);
  }

  flightLogTick(now);
  serialLogCommand();

  vTaskDelay(pdMS_TO_TICKS(20));
}

#elif defined(ESPFC_HAL_MULTI_CORE_RP2040)

bool core1_separate_stack = true;
volatile bool setup_done = false;

// RP2040 multicore
// TODO: https://emalliab.wordpress.com/2021/04/18/raspberry-pi-pico-arduino-core-and-timers/
void setup()
{
  espfc.load();
  espfc.begin();
  setup_done = true;
}

void loop()
{
  espfc.update();
}

void setup1()
{
  while (!setup_done)
    ;
}

void loop1()
{
  espfc.updateOther();
}

#else
#error "No RTOS defined for multicore board"
#endif

#else

// single core
void setup()
{
  espfc.load();
  espfc.begin();
}

void loop()
{
  espfc.update();
  espfc.updateOther();
}

#endif
