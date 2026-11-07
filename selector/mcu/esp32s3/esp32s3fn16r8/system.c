/**
 * @file system.c
 * @brief ESP32-S3: the watchdogs the ROM leaves armed, the first lines of the log, the idle of the selector
 */
#include <stdint.h>
#include "dmsel_platform.h"
#include "dmsel_mcu.h"

#define REG(a)                  (*(volatile uint32_t*)(a))
#define RTC_CNTL_BASE           0x60008000u
#define RTC_WDTCONFIG0         (RTC_CNTL_BASE + 0x98)
#define RTC_WDTWPROTECT        (RTC_CNTL_BASE + 0xB0)
#define RTC_SWD_CONF           (RTC_CNTL_BASE + 0xB4)
#define RTC_SWD_WPROTECT       (RTC_CNTL_BASE + 0xB8)
#define TIMG0_BASE              0x6001F000u
#define TIMG1_BASE              0x60020000u
#define TIMG_WDTCONFIG0        0x48u
#define TIMG_WDTWPROTECT       0x64u
#define WDT_WKEY                0x50D83AA1u
#define SWD_WKEY                0x8F1D312Au
#define RTC_WDT_EN              (1u << 31)
#define RTC_WDT_FLASHBOOT       (1u << 12)
#define TIMG_WDT_EN             (1u << 31)
#define TIMG_WDT_FLASHBOOT      (1u << 14)
#define SWD_AUTO_FEED_EN        (1u << 31)

extern void ets_delay_us( uint32_t us );

/** The ROM arms the watchdogs of the RTC and of the timer group 0 for the time of the boot (the "flash boot protection"); the
 *  ESP-IDF bootloader switches the protection off. The super watchdog cannot be stopped: it is fed by the hardware. */
static void watchdogs_off( void )
{
    REG( RTC_WDTWPROTECT ) = WDT_WKEY;
    REG( RTC_WDTCONFIG0 ) &= ~(RTC_WDT_EN | RTC_WDT_FLASHBOOT);
    REG( RTC_WDTWPROTECT ) = 0;
    REG( RTC_SWD_WPROTECT ) = SWD_WKEY;
    REG( RTC_SWD_CONF ) |= SWD_AUTO_FEED_EN;
    REG( RTC_SWD_WPROTECT ) = 0;
    REG( TIMG0_BASE + TIMG_WDTWPROTECT ) = WDT_WKEY;
    REG( TIMG0_BASE + TIMG_WDTCONFIG0 ) &= ~(TIMG_WDT_EN | TIMG_WDT_FLASHBOOT);
    REG( TIMG0_BASE + TIMG_WDTWPROTECT ) = 0;
    REG( TIMG1_BASE + TIMG_WDTWPROTECT ) = WDT_WKEY;
    REG( TIMG1_BASE + TIMG_WDTCONFIG0 ) &= ~(TIMG_WDT_EN | TIMG_WDT_FLASHBOOT);
    REG( TIMG1_BASE + TIMG_WDTWPROTECT ) = 0;
}

static void console_hex( const char* label, uint32_t value )
{
    char text[48];
    unsigned n = 0, i;

    while( *label != 0 && n < 28 ) text[n++] = *label++;
    text[n++] = '0';
    text[n++] = 'x';
    for( i = 0; i < 8; i++ ) text[n++] = "0123456789abcdef"[(value >> (28 - 4 * i)) & 0xF];
    text[n++] = '\n';
    text[n] = 0;
    dmsel_mcu_console( text );
}

void dmsel_mcu_init( void )
{
    int result;

    watchdogs_off();
    dmsel_mcu_console( "\ndmsel: esp32s3\n" );
    result = dmsel_mcu_flash_init();
    console_hex( "dmsel: flash map ", (uint32_t)result );
    // The first word of the flash: the header of the image of the selector itself (e9 ...), if the mapping works
    console_hex( "dmsel: flash[0] ", *(const volatile uint32_t*)DMSEL_MCU_FLASH_ADDRESS );
}

void dmsel_mcu_idle( void )
{
    unsigned i;

    // The selector stays here when nothing can be started: say so, so that a terminal opened later sees it as well
    dmsel_mcu_console( "dmsel: idle, nothing to start\n" );
    for( i = 0; i < 20; i++ )
    {
        ets_delay_us( 100000 );
    }
}

/** NOT IMPLEMENTED: the layout of the board has to keep DMSEL_WATCHDOG_MS at 0 (the RTC watchdog can do it) */
void dmsel_mcu_watchdog_start( void* user, uint32_t timeout_ms )
{
    (void)user;
    (void)timeout_ms;
}
