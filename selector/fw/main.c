/**
 * @file main.c
 * @brief The selector: the log, the table for the firmware and the start of the chosen bank
 *
 * The same for every platform; what is specific is in arch/ and mcu/ (see include/dmsel_platform.h), and in the configs/
 * of dmboot: the layout of the flash (board), the memory map and the entry (mcu, arch).
 */
#include <stdint.h>
#include "dmlog.h"
#include "dmsel_table.h"
#include "dmsel_platform.h"
#include "dmsel_mcu.h"
#include "dmsel_layout.h"

#define LOG_SIZE                4096u
#define SELECTOR_VERSION        1

static uint8_t g_scratch[DMSEL_STORE_SIZE] __attribute__(( aligned( 8 ) ));
static uint8_t g_log_storage[LOG_SIZE] __attribute__(( aligned( 8 ) ));
static dmlog_ctx_t g_log;
static dmsel_t g_state;

__attribute__(( weak )) void dmsel_mcu_init( void ) {}
__attribute__(( weak )) void dmsel_mcu_console( const char* text ) { (void)text; }
__attribute__(( weak )) void dmsel_mcu_idle( void ) { dmsel_arch_idle(); }
__attribute__(( weak )) uint32_t dmsel_mcu_prepare_jump( void* user, uint32_t address ) { (void)user; return address; }

static void log_text( const char* text )
{
    if( g_log != NULL )
    {
        dmlog_puts( g_log, text );
    }
    dmsel_mcu_console( text );
}

static void port_log( void* user, const char* text )
{
    (void)user;
    log_text( text );
}

/** The jump of a chip whose flash is not in the memory yet needs the mcu to prepare it first */
static void port_jump( void* user, uint32_t address )
{
    address = dmsel_mcu_prepare_jump( user, address );
    if( address == 0 )
    {
        log_text( "dmsel: the image could not be brought into the memory\n" );
        return;
    }
    dmsel_arch_jump( user, address );
}

/** The selector's own port (it logs), and the one behind the table (the firmware has the log of its own) */
static const dmsel_port_t g_port =
{
    .flash = (const uint8_t*)DMSEL_MCU_FLASH_ADDRESS, .erase = dmsel_mcu_erase, .program = dmsel_mcu_program,
    .jump = port_jump, .log = port_log, .watchdog_start = dmsel_mcu_watchdog_start,
    .user = (void*)&dmsel_layout,
};
static const dmsel_port_t g_port_for_firmware =
{
    .flash = (const uint8_t*)DMSEL_MCU_FLASH_ADDRESS, .erase = dmsel_mcu_erase, .program = dmsel_mcu_program,
    .jump = port_jump, .log = 0, .watchdog_start = dmsel_mcu_watchdog_start,
    .user = (void*)&dmsel_layout,
};

#ifdef DMSEL_SELFTEST
#define SELFTEST_ID             0x54454C53u     //!< "SLET"

static void log_value( const char* label, int32_t value )
{
    char text[48];
    char digits[12];
    unsigned n = 0, d = 0;
    uint32_t v = value < 0 ? (uint32_t)(-(int64_t)value) : (uint32_t)value;

    while( *label != 0 && n < 30 ) text[n++] = *label++;
    if( value < 0 ) text[n++] = '-';
    do { digits[d++] = (char)('0' + v % 10); v /= 10; } while( v != 0 );
    while( d != 0 ) text[n++] = digits[--d];
    text[n++] = '\n';
    text[n] = 0;
    log_text( text );
}

/** Bring-up of a port: the store keeps a counter of the starts - a flash that cannot be erased or programmed shows here */
static void selftest( void )
{
    uint32_t starts = 0;

    log_value( "dmsel: selftest read: ", dmsel_persist_read( &g_state, SELFTEST_ID, &starts, sizeof(starts) ) );
    log_value( "dmsel: selftest starts: ", (int32_t)starts );
    starts++;
    log_value( "dmsel: selftest write: ", dmsel_persist_write( &g_state, SELFTEST_ID, &starts, sizeof(starts) ) );
    starts = 0;
    log_value( "dmsel: selftest read back: ", dmsel_persist_read( &g_state, SELFTEST_ID, &starts, sizeof(starts) ) );
    log_value( "dmsel: selftest starts now: ", (int32_t)starts );
}
#endif

static int table_init( dmsel_t* s, int running, uint8_t* scratch )
{
    int r = dmsel_init( s, &dmsel_layout, &g_port_for_firmware, scratch );

    if( running == DMSEL_RUNNING_STARTED )
    {
        running = g_state.running < dmsel_layout.bank_count ? (int)g_state.running : -1;
    }
    s->running = (running >= 0 && (uint32_t)running < dmsel_layout.bank_count) ? (uint8_t)running : DMSEL_MAX_BANKS;
    return r;
}

__attribute__(( section( ".dmsel_table" ), used ))
const dmsel_table_t g_table =
{
    .magic = DMSEL_TABLE_MAGIC, .abi = DMSEL_TABLE_ABI, .table_size = sizeof(dmsel_table_t),
    .state_size = sizeof(dmsel_t), .scratch_size = DMSEL_STORE_SIZE, .version = SELECTOR_VERSION,
    .log_address = (uint32_t)(uintptr_t)g_log_storage, .log_size = LOG_SIZE,
    .init = table_init, .bank_count = dmsel_bank_count, .running_bank = dmsel_running_bank,
    .get_info = dmsel_get_info, .verify = dmsel_verify, .select = dmsel_select, .ready = dmsel_ready,
    .persist_write = dmsel_persist_write, .persist_read = dmsel_persist_read,
};

int main( void )
{
    dmsel_mcu_init();
    g_log = dmlog_create( g_log_storage, LOG_SIZE );
    log_text( "dmsel: selector started\n" );
    dmsel_init( &g_state, &dmsel_layout, &g_port, g_scratch );
#ifdef DMSEL_SELFTEST
    selftest();
#endif
    dmsel_boot( &g_state );
    // Only when nothing can be started: the log stays in the RAM for the debugger
    for( ;; )
    {
        dmsel_mcu_idle();
    }
}
