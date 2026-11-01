/**
 * @file port_shim.c
 * @brief What the FreeRTOS port of Espressif (GCC_XTENSA_ESP32) takes from ESP-IDF and this project does not have
 *
 * One core, nothing of the heap, the watchdogs, the cache or the second core of the IDF: the replacements are what the port
 * needs to link, and no more than that.
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

extern int ets_get_cpu_frequency( void );               /* the ROM: the frequency in MHz that the boot of the chip left */

/** The frequency of the CPU in Hz: the counter of the core (CCOUNT) drives the tick of the scheduler */
int esp_clk_cpu_freq( void )
{
    return ets_get_cpu_frequency() * 1000000;
}

/* port_common.c of the port: the scheduler of a core is running */
volatile unsigned port_xSchedulerRunning[ 1 ] = { 0 };

/* A memory a task may live in: all of the internal RAM is (the checks of ESP-IDF tell internal from external RAM) */
bool xPortCheckValidTCBMem( const void * ptr )
{
    return ptr != NULL;
}

bool xPortcheckValidStackMem( const void * ptr )
{
    return ptr != NULL;
}

/* The stack overflow watch of the port: a watchpoint of the core (not set) */
int esp_cpu_set_watchpoint( int id, const void * addr, size_t size, int flags )
{
    ( void ) id; ( void ) addr; ( void ) size; ( void ) flags;
    return 0;
}

/* The port of a core asks the other core to yield: there is one core */
void esp_crosscore_int_send_yield( int core_id )
{
    ( void ) core_id;
}

/* ESP-IDF starts the application and the main task here: dmboot starts its own */
void esp_startup_start_app_common( void )
{
}

/* The time of ESP-IDF's timer: for the run time statistics of the port, not used */
int64_t esp_timer_get_time( void )
{
    return 0;
}

/* The handlers of the interrupts and of the exceptions that nobody has installed (the tables of xtensa_intr_asm.S start with
 * them): there is nothing to do with them, but to stop for the debugger. In the IRAM: an interrupt does not wait for the cache. */
extern void _xt_panic( void );

__attribute__(( section( ".iram1" ) )) void xt_unhandled_interrupt( void * arg )
{
    ( void ) arg;
    _xt_panic();
}

__attribute__(( section( ".iram1" ) )) void xt_unhandled_exception( void * frame )
{
    ( void ) frame;
    _xt_panic();
}
