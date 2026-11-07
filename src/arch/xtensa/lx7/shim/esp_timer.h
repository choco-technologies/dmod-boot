/* The timer of ESP-IDF, for the run time statistics of the FreeRTOS port (not used here) */
#ifndef ESP_TIMER_H
#define ESP_TIMER_H
#include <stdint.h>
int64_t esp_timer_get_time( void );
#endif
