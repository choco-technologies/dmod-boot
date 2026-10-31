/**
 * @file main.c
 * @brief The selector for the STM32F746G-DISCO: the layout of the flash, the log, the table for the firmware
 *
 * Flash:  S0 selector | S1 store (state of the banks, persistent items) | S2, S3 file systems of the banks |
 *         S4+S5 bank A (384 kB) | S6+S7 bank B (384 kB of the 512 kB)
 */
#include <stdint.h>
#include "dmlog.h"
#include "dmsel_table.h"
#include "dmsel_f7.h"

#ifndef DMSEL_WATCHDOG_MS
#define DMSEL_WATCHDOG_MS       0       // The firmware has to feed the watchdog from the moment it starts: 0 until it does
#endif
#define LOG_SIZE                4096u
#define SCRATCH_SIZE            0x8000u
#define SELECTOR_VERSION        1

static const dmsel_layout_t g_layout =
{
    .flash_address = 0x08000000u,
    .store_offset = DMSEL_F7_STORE_OFFSET,
    .store_size = DMSEL_F7_STORE_SIZE,
    .bank_count = 2,
    .banks = { { 0x20000u, 0x60000u }, { 0x80000u, 0x60000u } },
    .max_tries = 3,
    .watchdog_ms = DMSEL_WATCHDOG_MS,
};

static uint8_t g_scratch[SCRATCH_SIZE] __attribute__(( aligned( 8 ) ));
static uint8_t g_log_storage[LOG_SIZE] __attribute__(( aligned( 8 ) ));
static dmlog_ctx_t g_log;
static dmsel_t g_state;

static void port_log( void* user, const char* text )
{
    (void)user;
    if( g_log != NULL )
    {
        dmlog_puts( g_log, text );
    }
}

/** The selector's own port (it logs), and the one behind the table (the firmware has the log of its own) */
static const dmsel_port_t g_port =
{
    .flash = (const uint8_t*)0x08000000u, .erase = dmsel_f7_erase, .program = dmsel_f7_program,
    .jump = dmsel_f7_jump, .log = port_log, .watchdog_start = dmsel_f7_watchdog_start,
};
static const dmsel_port_t g_port_for_firmware =
{
    .flash = (const uint8_t*)0x08000000u, .erase = dmsel_f7_erase, .program = dmsel_f7_program,
    .jump = dmsel_f7_jump, .log = 0, .watchdog_start = dmsel_f7_watchdog_start,
};

static int table_init( dmsel_t* s, int running, uint8_t* scratch )
{
    int r = dmsel_init( s, &g_layout, &g_port_for_firmware, scratch );

    s->running = (running >= 0 && (uint32_t)running < g_layout.bank_count) ? (uint8_t)running : DMSEL_MAX_BANKS;
    return r;
}

__attribute__(( section( ".dmsel_table" ), used ))
const dmsel_table_t g_table =
{
    .magic = DMSEL_TABLE_MAGIC, .abi = DMSEL_TABLE_ABI, .table_size = sizeof(dmsel_table_t),
    .state_size = sizeof(dmsel_t), .scratch_size = DMSEL_F7_STORE_SIZE, .version = SELECTOR_VERSION,
    .log_address = (uint32_t)(uintptr_t)g_log_storage, .log_size = LOG_SIZE,
    .init = table_init, .bank_count = dmsel_bank_count, .running_bank = dmsel_running_bank,
    .get_info = dmsel_get_info, .verify = dmsel_verify, .select = dmsel_select, .ready = dmsel_ready,
    .persist_write = dmsel_persist_write, .persist_read = dmsel_persist_read,
};

int main( void )
{
    g_log = dmlog_create( g_log_storage, LOG_SIZE );
    dmlog_puts( g_log, "dmsel: selector started\n" );
    dmsel_init( &g_state, &g_layout, &g_port, g_scratch );
    dmsel_boot( &g_state );
    // Only when nothing can be started: the log stays in the RAM for the debugger
    for( ;; )
    {
        __asm volatile ( "wfi" );
    }
}
