/* The heap of ESP-IDF, for the FreeRTOS port: the port asks where a task stack may be and whether the memory is internal */
#ifndef ESP_HEAP_CAPS_H
#define ESP_HEAP_CAPS_H
#include <stddef.h>
#include <stdint.h>
#define MALLOC_CAP_EXEC             (1 << 0)
#define MALLOC_CAP_32BIT            (1 << 1)
#define MALLOC_CAP_8BIT             (1 << 2)
#define MALLOC_CAP_INTERNAL         (1 << 11)
#define MALLOC_CAP_SPIRAM           (1 << 10)
#endif
