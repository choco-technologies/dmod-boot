/**
 * @file main.c
 * @brief The selector: the log, the table for the firmware and the start of the chosen bank
 *
 * The same for every platform; what is specific is in configs/ (see include/dmsel_platform.h): the core (arch), the chip
 * (mcu) and the layout of the flash (board).
 */
#include <stdint.h>
#include "dmlog.h"
#include "dmsel_table.h"
#include "dmsel_platform.h"
#include "dmsel_mcu.h"
#include "dmsel_board.h"

#define LOG_SIZE                4096u
#define SELECTOR_VERSION        1

static uint8_t g_scratch[DMSEL_BOARD_STORE_SIZE] __attribute__(( aligned( 8 ) ));
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
    .flash = (const uint8_t*)DMSEL_MCU_FLASH_ADDRESS, .erase = dmsel_mcu_erase, .program = dmsel_mcu_program,
    .jump = dmsel_arch_jump, .log = port_log, .watchdog_start = dmsel_mcu_watchdog_start,
    .user = (void*)&dmsel_board_layout,
};
static const dmsel_port_t g_port_for_firmware =
{
    .flash = (const uint8_t*)DMSEL_MCU_FLASH_ADDRESS, .erase = dmsel_mcu_erase, .program = dmsel_mcu_program,
    .jump = dmsel_arch_jump, .log = 0, .watchdog_start = dmsel_mcu_watchdog_start,
    .user = (void*)&dmsel_board_layout,
};

static int table_init( dmsel_t* s, int running, uint8_t* scratch )
{
    int r = dmsel_init( s, &dmsel_board_layout, &g_port_for_firmware, scratch );

    s->running = (running >= 0 && (uint32_t)running < dmsel_board_layout.bank_count) ? (uint8_t)running : DMSEL_MAX_BANKS;
    return r;
}

__attribute__(( section( ".dmsel_table" ), used ))
const dmsel_table_t g_table =
{
    .magic = DMSEL_TABLE_MAGIC, .abi = DMSEL_TABLE_ABI, .table_size = sizeof(dmsel_table_t),
    .state_size = sizeof(dmsel_t), .scratch_size = DMSEL_BOARD_STORE_SIZE, .version = SELECTOR_VERSION,
    .log_address = (uint32_t)(uintptr_t)g_log_storage, .log_size = LOG_SIZE,
    .init = table_init, .bank_count = dmsel_bank_count, .running_bank = dmsel_running_bank,
    .get_info = dmsel_get_info, .verify = dmsel_verify, .select = dmsel_select, .ready = dmsel_ready,
    .persist_write = dmsel_persist_write, .persist_read = dmsel_persist_read,
};

int main( void )
{
    g_log = dmlog_create( g_log_storage, LOG_SIZE );
    dmlog_puts( g_log, "dmsel: selector started\n" );
    dmsel_init( &g_state, &dmsel_board_layout, &g_port, g_scratch );
    dmsel_boot( &g_state );
    // Only when nothing can be started: the log stays in the RAM for the debugger
    for( ;; )
    {
        __asm volatile ( "wfi" );
    }
}
