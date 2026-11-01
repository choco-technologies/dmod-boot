/* ESP-IDF >= 5.2: the compare-and-set of the external RAM is esp_cpu_compare_and_set() of esp_cpu.h; the original header is
   used when there is one. */
#pragma once
#if __has_include_next(<soc/compare_set.h>)
    #include_next <soc/compare_set.h>
#else
    #include <esp_cpu.h>
    #define compare_and_set_extram( addr, compare, set )    do { *( set ) = esp_cpu_compare_and_set( ( volatile uint32_t * ) ( addr ), ( compare ), *( set ) ) ? ( compare ) : *( set ); } while( 0 )
#endif
