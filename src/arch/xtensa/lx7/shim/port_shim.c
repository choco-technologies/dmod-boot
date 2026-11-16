/**
 * @file port_shim.c
 * @brief What the FreeRTOS port of Espressif (GCC_XTENSA_ESP32) takes from ESP-IDF and this project does not have
 *
 * One core, nothing of the heap, the watchdogs, the cache or the second core of the IDF: the replacements are what the port
 * needs to link, and no more than that.
 */
#include "dmod.h"
#include "dmosi.h"
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

/* A fault that cannot be contained to a process (src/arch/xtensa/lx7/fault.c): what is known goes where _xt_panic keeps it, and the system resets */
void dmboot_reboot_on_fault( uint32_t cause, uint32_t address, uint32_t pc, uint32_t ps, uint32_t a0, uint32_t sp )
{
    dmboot_last_exception[ 0 ] = cause;
    dmboot_last_exception[ 1 ] = address;
    dmboot_last_exception[ 2 ] = pc;
    dmboot_last_exception[ 3 ] = ps;
    dmboot_last_exception[ 4 ] = a0;
    dmboot_last_exception[ 5 ] = sp;
    for( int i = 6; i < DMBOOT_EXCEPTION_WORDS; i++ )
    {
        dmboot_last_exception[ i ] = 0u;
    }
    _xt_panic();
    for( ;; )
    {
    }
}

/*
 * What the last run left when it ended in _xt_panic (panic.S): printed once, at the start that follows. The record is in the RTC slow memory,
 * which a reset does not clear: [0] the mark, [1..16] dmboot_last_exception, [17..21] EXCCAUSE, EXCVADDR, EPC1, EPC2, DEPC.
 */
void dmboot_report_last_crash( void )
{
    volatile uint32_t * r = ( volatile uint32_t * ) 0x50001F40u;

    if( r[ 0 ] != 0xC4A5E0D1u )
    {
        return;
    }
    r[ 0 ] = 0xC4A5E0D2u;                   /* reported (the record stays: a debugger can still read it) */
    DMOD_LOG_ERROR( "dmboot: the last run ended in a crash - cause %u at 0x%08x, pc 0x%08x, ps 0x%08x, a0 0x%08x, sp 0x%08x\n",
                 ( unsigned ) r[ 1 ], ( unsigned ) r[ 2 ], ( unsigned ) r[ 3 ], ( unsigned ) r[ 4 ], ( unsigned ) r[ 5 ], ( unsigned ) r[ 6 ] );
    DMOD_LOG_ERROR( "dmboot: callers 0x%08x 0x%08x 0x%08x 0x%08x; at the panic: exccause %u excvaddr 0x%08x epc1 0x%08x epc2 0x%08x depc 0x%08x\n",
                 ( unsigned ) r[ 7 ], ( unsigned ) r[ 8 ], ( unsigned ) r[ 9 ], ( unsigned ) r[ 10 ],
                 ( unsigned ) r[ 17 ], ( unsigned ) r[ 18 ], ( unsigned ) r[ 19 ], ( unsigned ) r[ 20 ], ( unsigned ) r[ 21 ] );
}

/*
 * The way out of a hang that is no exception (a deadlock with the interrupts off, a task that never lets go of the CPU): the RTC watchdog resets
 * the system unless a task of the lowest priority feeds it - a task that is starved (or a tick that does not come) is a system that is hung.
 * The exceptions do not wait for it: _xt_panic resets at once.
 */
#define RTC_WDT_CONFIG0     ( *( volatile uint32_t * ) 0x60008098u )
#define RTC_WDT_CONFIG1     ( *( volatile uint32_t * ) 0x6000809Cu )
#define RTC_WDT_FEED        ( *( volatile uint32_t * ) 0x600080ACu )
#define RTC_WDT_PROTECT     ( *( volatile uint32_t * ) 0x600080B0u )
#define RTC_WDT_KEY         0x50D83AA1u
#define WATCHDOG_TICKS      3000000u        /* of the slow clock of the RTC (about 136 kHz): about 22 s */
#define WATCHDOG_FEED_MS    1000u

static void watchdog_feeder( void * arg )
{
    ( void ) arg;
    for( ;; )
    {
        RTC_WDT_PROTECT = RTC_WDT_KEY;
        RTC_WDT_FEED = 0x80000000u;               /* RTC_CNTL_WDT_FEED is bit 31 */
        RTC_WDT_PROTECT = 0u;
        dmosi_thread_sleep( WATCHDOG_FEED_MS );
    }
}

void dmboot_start_watchdog( void )
{
    dmosi_thread_t feeder = dmosi_thread_create( watchdog_feeder, NULL, 1, 2048, "watchdog", NULL );
    if( feeder == NULL )
    {
        DMOD_LOG_ERROR( "dmboot: no thread for the watchdog - the system runs without it\n" );
        return;                             /* no feeder, no watchdog: it must never be on without one */
    }
    RTC_WDT_PROTECT = RTC_WDT_KEY;
    RTC_WDT_CONFIG1 = WATCHDOG_TICKS;
    /* enabled; the first stage resets the system; reset signals of the longest length; the CPUs are reset too */
    RTC_WDT_CONFIG0 = ( 1u << 31 ) | ( 3u << 28 ) | ( 7u << 16 ) | ( 7u << 13 ) | ( 1u << 11 ) | ( 1u << 10 );
    RTC_WDT_FEED = 0x80000000u;               /* RTC_CNTL_WDT_FEED is bit 31 */
    RTC_WDT_PROTECT = 0u;
    DMOD_LOG_INFO( "dmboot: the watchdog is on (a reset after %u ticks of the RTC clock without a feed)\n", ( unsigned ) WATCHDOG_TICKS );
}
