/**
 * @file main.c
 * @brief A test image of a bank: what a firmware would do with the table of the selector, reported into the RAM for
 *        openocd (g_result at 0x20010000), and driven by a command written to g_cmd (0x20010100)
 *
 * Built twice, for the bank A and the bank B (-DBANK_INDEX=...); it blinks the LD1 LED (PI1).
 */
#include <stdint.h>
#include "dmsel_table.h"

#define REG(a)  (*(volatile uint32_t*)(a))

volatile uint32_t g_result[32] __attribute__(( section( ".result" ) ));
volatile uint32_t g_cmd __attribute__(( section( ".cmd" ) ));
static uint8_t g_scratch[0x8000] __attribute__(( aligned( 8 ) ));
static dmsel_t g_state __attribute__(( aligned( 8 ) ));
static const dmsel_table_t* g_table;

static void report( void )
{
    dmsel_bank_info_t info;
    int b;

    g_result[2] = (uint32_t)g_table->bank_count( &g_state );
    g_result[3] = (uint32_t)g_table->running_bank( &g_state );
    for( b = 0; b < 2; b++ )
    {
        info.struct_size = sizeof(info);
        g_table->get_info( &g_state, b, &info );
        g_result[4 + b] = info.state;
        g_result[6 + b] = info.version;
        g_result[14 + b] = info.tries;
    }
}

int main( void )
{
    uint32_t n = 0;

    REG( 0x40023830u ) |= (1u << 8);                    // GPIOI clock
    REG( 0x40022000u ) = (REG( 0x40022000u ) & ~(3u << 2)) | (1u << 2);     // PI1 output

    g_table = (const dmsel_table_t*)DMSEL_TABLE_ADDRESS;
    g_result[1] = g_table->magic == DMSEL_TABLE_MAGIC ? 0x600D : 0xBAD;
    if( g_result[1] != 0x600D )
    {
        for( ;; ) {}
    }
    g_result[9] = (uint32_t)g_table->init( &g_state, BANK_INDEX, g_scratch );
    g_result[16] = g_table->version;
    g_result[17] = g_table->log_address;
    report();

    for( ;; )
    {
        uint32_t cmd = g_cmd;

        g_result[0] = ++n;
        if( (n & 0x3FFFF) == 0 ) REG( 0x40022014u ) ^= (1u << 1);       // ODR: blink
        if( cmd != 0 )
        {
            g_cmd = 0;
            if( cmd == 1 )          // the other bank on trial, and a reset
            {
                int other = 1 - BANK_INDEX;
                g_result[10] = (uint32_t)g_table->verify( &g_state, other );
                g_result[11] = (uint32_t)g_table->select( &g_state, other, 1 );
                REG( 0xE000ED0Cu ) = 0x05FA0004u;       // SYSRESETREQ
            }
            else if( cmd == 2 )     // it runs properly
            {
                g_result[12] = (uint32_t)g_table->ready( &g_state );
            }
            else if( cmd == 3 )     // the persistent data
            {
                uint8_t buf[16] = { 0 };
                g_result[18] = (uint32_t)g_table->persist_write( &g_state, 0x1234, "persist", 8 );
                g_result[19] = (uint32_t)g_table->persist_read( &g_state, 0x1234, buf, sizeof(buf) );
                g_result[20] = (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) | ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
            }
            else if( cmd == 4 )     // back to the other bank for good
            {
                g_result[13] = (uint32_t)g_table->select( &g_state, 1 - BANK_INDEX, 0 );
                REG( 0xE000ED0Cu ) = 0x05FA0004u;
            }
            report();
        }
    }
}
