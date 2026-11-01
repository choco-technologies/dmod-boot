/* ESP-IDF >= 5.2: spinlock.h is on the top level of esp_hw_support/include; the original header is used when there is one. */
#pragma once
#if __has_include_next(<soc/spinlock.h>)
    #include_next <soc/spinlock.h>
#else
    #include <spinlock.h>
#endif
