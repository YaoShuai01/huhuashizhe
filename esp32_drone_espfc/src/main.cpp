#include <Arduino.h>
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
  printf("[ESPFC] gyro=%d accel=%d mag=%d baro=%d rate=%dHz\n",
         (int)espfc.isGyroReady(), (int)espfc.isAccelReady(),
         (int)espfc.isMagReady(), (int)espfc.isBaroReady(), espfc.gyroRate());
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

void setup()
{
  // Do NOT call disableCore0WDT() here: on Arduino core 3.x it only removes
  // the core-0 idle task from the task WDT, whose idle hook then logs
  // "esp_task_wdt_reset: task not found" every few milliseconds.
  espfc.load();
  Task::create(gyroTask, "gyroTask", 8192, nullptr, Task::Priority::High, 1);
  Task::create(pidTask, "pidTask", 8192, nullptr, Task::Priority::Low, 0);
  // Keep the Arduino loop task alive: it feeds the task watchdog. Deleting it
  // causes "esp_task_wdt_reset: task not found" and a boot loop on core 3.x.
}

// 全彩灯心跳：蓝 1.5 秒一次、绿 3 秒一次
enum StatusLedColor
{
  STATUS_LED_OFF,
  STATUS_LED_BLUE,
  STATUS_LED_GREEN,
};

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
