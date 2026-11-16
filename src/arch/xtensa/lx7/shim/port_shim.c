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

/**
 * The frequency of the CPU in Hz: the counter of the core (CCOUNT) drives the tick of the scheduler, and the port reads this
 * once, when the scheduler starts. It is the frequency that the clocks are configured to (DMOSI_CPU_CLOCK_HZ of the MCU,
 * the same constant that the tick of the ARM ports counts with): dmclk brings the CPU there, a little after the start.
 */
int esp_clk_cpu_freq( void )
{
    return ( int ) DMOSI_CPU_CLOCK_HZ;
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

/*
 * What the last unhandled exception was, for a debugger (the stack of a task may be in the external RAM, which JTAG does not read; this is in
 * the internal one): [0] the cause, [1] the address, [2] the PC, [3] the PS, [4] a0, [5] a1, [6..] the callers (the return addresses of the
 * windowed frames, as the stack keeps them). Read it with the address of the symbol from the ELF.
 */
#define DMBOOT_EXCEPTION_WORDS  16
volatile uint32_t dmboot_last_exception[ DMBOOT_EXCEPTION_WORDS ];

__attribute__(( section( ".iram1" ) )) void xt_unhandled_exception( void * frame )
{
    /* XtExcFrame: exit, pc, ps, a0, a1, a2.. a15, sar, exccause, excvaddr */
    const uint32_t * f = frame;
    uint32_t sp = f[ 4 ];

    dmboot_last_exception[ 0 ] = f[ 20 ];
    dmboot_last_exception[ 1 ] = f[ 21 ];
    dmboot_last_exception[ 2 ] = f[ 1 ];
    dmboot_last_exception[ 3 ] = f[ 2 ];
    dmboot_last_exception[ 4 ] = f[ 3 ];
    dmboot_last_exception[ 5 ] = f[ 4 ];

    uint32_t pc = ( f[ 3 ] & 0x3fffffffu ) | 0x40000000u;
    for( int i = 6; i < DMBOOT_EXCEPTION_WORDS; i++ )
    {
        dmboot_last_exception[ i ] = pc;
        if( sp < 0x3c000000u || sp > 0x3fffffffu || ( sp & 3u ) != 0u )
        {
            break;
        }
        pc = ( *( const uint32_t * ) ( sp - 16u ) & 0x3fffffffu ) | 0x40000000u;
        sp = *( const uint32_t * ) ( sp - 12u );
    }
    _xt_panic();
}

/*
 * The interrupts of the CPU for the modules: the vector of the port calls the handler of _xt_interrupt_table for the line that
 * fired. Each line that nothing took gets the handler that hands the line to dmod (Dmod_IrqAll), where the modules register theirs
 * (DMOD_IRQ_HANDLER(line)) - what the generic handler of the ARM ports does with the number of the IRQ.
 */
typedef struct
{
    void ( * handler )( void * );
    void * arg;
} xt_interrupt_entry_t;

extern xt_interrupt_entry_t _xt_interrupt_table[ 32 ];
extern void xt_unhandled_interrupt( void * );
extern void Dmod_IrqAll( int IrqNumber );

static void dmod_irq_dispatch( void * line )
{
    Dmod_IrqAll( ( int ) ( uintptr_t ) line );
}

void dmboot_xtensa_irq_init( int count )
{
    if( count > 32 )
    {
        count = 32;
    }

    for( int line = 0; line < count; line++ )
    {
        /* the lines that the port or the firmware took (the tick, the yield) have a handler of their own */
        if( _xt_interrupt_table[ line ].handler == xt_unhandled_interrupt )
        {
            _xt_interrupt_table[ line ].handler = dmod_irq_dispatch;
            _xt_interrupt_table[ line ].arg = ( void * ) ( uintptr_t ) line;
        }
    }
}
