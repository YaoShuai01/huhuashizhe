#include <Espfc.hpp>
#include <Hal/FastCode.hpp>
#include <Hal/Platform.hpp>
#include <Hal/Task.hpp>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

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
  espfc.beginGyroTimer(gyroTimerIsr);
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

void loop()
{
  vTaskDelay(pdMS_TO_TICKS(1000));
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
