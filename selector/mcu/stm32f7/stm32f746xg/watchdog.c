/**
 * @file watchdog.c
 * @brief STM32F7: the independent watchdog (IWDG) for an image on trial
 */
#include <stdint.h>
#include "dmsel_platform.h"

#define REG(a)          (*(volatile uint32_t*)(a))

void dmsel_mcu_watchdog_start( void* user, uint32_t timeout_ms )
{
    uint32_t reload = timeout_ms / 8u;          // LSI 32 kHz / 256 = 125 Hz: 8 ms per tick

    (void)user;
    if( reload > 0xFFFu ) reload = 0xFFFu;
    if( reload == 0 ) reload = 1;
    REG( 0xE0042008u ) |= (1u << 12);           // DBGMCU: the watchdog stops while the core is halted by the debugger
    REG( 0x40003000u ) = 0xCCCCu;               // IWDG: start (cannot be stopped)
    REG( 0x40003000u ) = 0x5555u;
    REG( 0x40003004u ) = 6;                     // /256
    REG( 0x40003008u ) = reload;
    while( REG( 0x4000300Cu ) != 0 ) {}
    REG( 0x40003000u ) = 0xAAAAu;
}
