/* ESP-IDF >= 5.2 has no soc/cpu.h (esp_cpu.h and xt_utils.h took its place); the FreeRTOS port still includes it.
   With an older ESP-IDF the original header is used. */
#pragma once
#if __has_include_next(<soc/cpu.h>)
    #include_next <soc/cpu.h>
#else
    #include <xtensa_api.h>
    #include <esp_cpu.h>
    #include <xt_utils.h>
    /* the name of the trigger of the watchpoint before esp_cpu.h */
    #define ESP_WATCHPOINT_STORE    ESP_CPU_WATCHPOINT_STORE
#endif
