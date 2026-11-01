/* The configuration (Kconfig) of ESP-IDF that the headers of the chip and the FreeRTOS port read: the one core, the tick on the
   counter of the core, nothing of the rest (PSRAM, power management, tracing, the watchdogs of the IDF) */
#ifndef SDKCONFIG_H
#define SDKCONFIG_H

#define CONFIG_IDF_TARGET "esp32s3"
#define CONFIG_IDF_TARGET_ESP32S3 1
#define CONFIG_FREERTOS_UNICORE 1
#define CONFIG_ESP_SYSTEM_SINGLE_CORE_MODE 1
#define CONFIG_FREERTOS_SYSTICK_USES_CCOUNT 1
#define CONFIG_FREERTOS_CORETIMER_0 1
#define CONFIG_FREERTOS_ISR_STACKSIZE 1536
#define CONFIG_FREERTOS_ASSERT_FAIL_ABORT 1
#define CONFIG_FREERTOS_NO_AFFINITY 0xFFFFFFFFu     /* tskNO_AFFINITY of the kernel: (UBaseType_t) -1 */
#define CONFIG_ESP32S3_DEFAULT_CPU_FREQ_MHZ 240

#endif
