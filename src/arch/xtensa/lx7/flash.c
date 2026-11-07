/**
 * @file flash.c
 * @brief Erasing and programming the flash of the ESP32-S3 while the firmware runs from it (the port of dmflash)
 *
 * The code of the firmware is fetched from the flash through the instruction cache, its data (and the modules, the heap, the stacks)
 * are in the external RAM through the data cache: while the SPI works on the flash, neither cache can be served. So the work is done
 * with both caches suspended, the interrupts off, and from the internal RAM only: the code (section .iram1, with its literals), the
 * data (a page in .bss) and the stack. The stack of the caller may be in the external RAM (the heap puts it there first), so the
 * work runs in the handler of a software interrupt: on the stack of the interrupts (see run()).
 *
 * Only the ROM does the SPI work (esp_rom_spiflash_*, as the selector does): it knows the flash from the selector, which has told it
 * the size of the chip (selector/mcu/esp32s3/esp32s3fn16r8/flash.c). The ROM calls are by address (esp32s3.rom.ld of ESP-IDF).
 *
 * The functions are offered to the modules (dmflash's port) as the API "dmboot": the offset is the one in the chip. The core of
 * dmflash calls them one at a time (its mutex); they are not reentrant.
 */
#define DMOD_ENABLE_REGISTRATION ON
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include "dmod_defs.h"
#include "dmod_types.h"

#define IRAM                    __attribute__((section(".iram1"), noinline, used))

#define FLASH_WINDOW            0x3C000000UL    /* the flash, all of it, in the data cache window (mapped by the selector) */
#define FLASH_SIZE              0x1000000UL     /* the chip of the board: 16 MB */
#define SECTOR_SIZE             0x1000U
#define PAGE_SIZE               0x100U
#define FLASH_CPU_INTR          7U              /* the software interrupt of the CPU (level 1) that the work runs in */

/* ROM */
#define ROM_FLASH_ERASE_SECTOR  0x400009fcUL    /* int (uint32_t sector) */
#define ROM_FLASH_WRITE         0x40000a14UL    /* int (uint32_t dest, const uint32_t* src, int32_t len) */
#define ROM_CACHE_INVALIDATE_ADDR   0x400016b0UL /* void (uint32_t vaddr, uint32_t size) */
#define ROM_CACHE_SUSPEND_ICACHE    0x4000189cUL /* uint32_t (void) */
#define ROM_CACHE_RESUME_ICACHE     0x400018a8UL /* void (uint32_t autoload) */
#define ROM_CACHE_SUSPEND_DCACHE    0x400018b4UL /* uint32_t (void) */
#define ROM_CACHE_RESUME_DCACHE     0x400018c0UL /* void (uint32_t autoload) */

typedef struct
{
    void ( * handler )( void * );
    void * arg;
} xt_interrupt_entry_t;

extern xt_interrupt_entry_t _xt_interrupt_table[ 32 ];

typedef struct
{
    uint32_t    sector;                 /* erase: the number of the sector */
    uint32_t    offset;                 /* program: where in the chip */
    uint32_t    size;                   /* program: the bytes of page[] to write; 0: erase */
    int         result;
    volatile int done;
    uint32_t    page[PAGE_SIZE / 4U];   /* the data of a program: here, in the internal RAM */
} flash_work_t;

static flash_work_t work;

/* Runs with the caches off: nothing here (and nothing it calls) may be in the flash or the external RAM */
static IRAM void flash_work( void * arg )
{
    flash_work_t * w = ( flash_work_t * ) arg;
    uint32_t ps, dcache, icache;

    __asm__ __volatile__( "rsil %0, 15" : "=a"( ps ) :: "memory" );
    dcache = ( ( uint32_t ( * )( void ) )ROM_CACHE_SUSPEND_DCACHE )();
    icache = ( ( uint32_t ( * )( void ) )ROM_CACHE_SUSPEND_ICACHE )();

    if( w->size == 0U )
    {
        w->result = ( ( int ( * )( uint32_t ) )ROM_FLASH_ERASE_SECTOR )( w->sector );
    }
    else
    {
        w->result = ( ( int ( * )( uint32_t, const uint32_t *, int32_t ) )ROM_FLASH_WRITE )( w->offset, w->page, ( int32_t ) w->size );
    }
    /* The lines of the data cache that hold this part of the flash are old now */
    ( ( void ( * )( uint32_t, uint32_t ) )ROM_CACHE_INVALIDATE_ADDR )( ( uint32_t ) ( FLASH_WINDOW + ( w->size == 0U ? w->sector * SECTOR_SIZE : w->offset ) ),
                                                                     w->size == 0U ? SECTOR_SIZE : w->size );
    ( ( void ( * )( uint32_t ) )ROM_CACHE_RESUME_ICACHE )( icache );
    ( ( void ( * )( uint32_t ) )ROM_CACHE_RESUME_DCACHE )( dcache );
    __asm__ __volatile__( "wsr.ps %0; rsync" :: "a"( ps ) : "memory" );
    w->done = 1;
}

/*
 * The work runs in the handler of a software interrupt of the CPU: the port of the RTOS saves the interrupted context, spills the
 * register windows of the task and runs the handler on the stack of the interrupts, which is in the internal RAM (the stack of the
 * caller may be in the external RAM). Nothing else is needed to make the work safe.
 */
static int run( void )
{
    xt_interrupt_entry_t * entry = &_xt_interrupt_table[ FLASH_CPU_INTR ];
    uint32_t enable;

    work.done = 0;
    entry->handler = flash_work;
    entry->arg = &work;
    __asm__ __volatile__( "rsr.intenable %0" : "=a"( enable ) );
    __asm__ __volatile__( "wsr.intenable %0; rsync" :: "a"( enable | ( 1U << FLASH_CPU_INTR ) ) : "memory" );
    __asm__ __volatile__( "wsr.intset %0; rsync" :: "a"( 1U << FLASH_CPU_INTR ) : "memory" );
    while( !work.done )
    {
    }
    return work.result;
}

DMOD_BUILTIN_INPUT_API( dmboot, 1.0, int, _flash_erase, ( uint32_t offset, uint32_t size ) );

/** Erases the sectors (4 kB) of [offset, offset + size) of the chip */
DMOD_INPUT_API_DECLARATION( dmboot, 1.0, int, _flash_erase, ( uint32_t offset, uint32_t size ) )
{
    if( ( offset % SECTOR_SIZE ) != 0U || ( size % SECTOR_SIZE ) != 0U || offset > FLASH_SIZE || size > FLASH_SIZE - offset )
    {
        return -EINVAL;
    }
    for( uint32_t sector = offset / SECTOR_SIZE; sector < ( offset + size ) / SECTOR_SIZE; sector++ )
    {
        work.sector = sector;
        work.size = 0U;
        if( run() != 0 )
        {
            return -EIO;
        }
    }
    return 0;
}

DMOD_BUILTIN_INPUT_API( dmboot, 1.0, int, _flash_program, ( uint32_t offset, const void* data, uint32_t size ) );

/** Programs the bytes (a multiple of 4, at an address multiple of 4; the part erased before) at the offset in the chip */
DMOD_INPUT_API_DECLARATION( dmboot, 1.0, int, _flash_program, ( uint32_t offset, const void* data, uint32_t size ) )
{
    const uint8_t* src = (const uint8_t*)data;

    if( data == NULL || ( offset & 3U ) != 0U || ( size & 3U ) != 0U || offset > FLASH_SIZE || size > FLASH_SIZE - offset )
    {
        return -EINVAL;
    }
    while( size > 0U )
    {
        uint32_t n = PAGE_SIZE - ( offset & ( PAGE_SIZE - 1U ) );   /* up to the end of the page of the chip */

        if( n > size )
        {
            n = size;
        }
        memcpy( work.page, src, n );        /* the source may be in the external RAM or the flash: the caches work here */
        work.offset = offset;
        work.size = n;
        if( run() != 0 )
        {
            return -EIO;
        }
        offset += n;
        src += n;
        size -= n;
    }
    return 0;
}
