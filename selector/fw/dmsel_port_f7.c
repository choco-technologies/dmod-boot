/**
 * @file dmsel_port_f7.c
 * @brief The selector's port for the STM32F7 (RM0385): the flash, the jump, the watchdog
 *
 * Only the store sector is ever erased or programmed from here (a guard): a mistake of the core cannot touch the selector
 * or the banks. The flash is single bank: the CPU is stopped while a sector is erased (up to a second for 256 kB).
 */
#include <stdint.h>
#include "dmsel.h"
#include "dmsel_f7.h"

#define REG(a)          (*(volatile uint32_t*)(a))
#define FLASH_BASE      0x40023C00u
#define FLASH_ACR       REG( FLASH_BASE + 0x00 )
#define FLASH_KEYR      REG( FLASH_BASE + 0x04 )
#define FLASH_SR        REG( FLASH_BASE + 0x0C )
#define FLASH_CR        REG( FLASH_BASE + 0x10 )
#define SR_BSY          (1u << 16)
#define SR_ERRORS       0xF2u           // OPERR, WRPERR, PGAERR, PGPERR, ERSERR
#define SR_CLEAR        0xF3u
#define CR_PG           (1u << 0)
#define CR_SER          (1u << 1)
#define CR_SNB_MASK     (0xFu << 3)
#define CR_PSIZE_MASK   (3u << 8)
#define CR_PSIZE_X32    (2u << 8)
#define CR_STRT         (1u << 16)
#define CR_LOCK         (1u << 31)
#define ACR_ICEN        (1u << 9)
#define ACR_DCEN        (1u << 10)
#define ACR_ICRST       (1u << 11)
#define ACR_DCRST       (1u << 12)

static const struct { uint32_t offset, size; } g_sectors[8] =
{
    { 0x00000, 0x08000 }, { 0x08000, 0x08000 }, { 0x10000, 0x08000 }, { 0x18000, 0x08000 },
    { 0x20000, 0x20000 }, { 0x40000, 0x40000 }, { 0x80000, 0x40000 }, { 0xC0000, 0x40000 },
};

static int flash_wait( void )
{
    while( FLASH_SR & SR_BSY ) {}
    return (FLASH_SR & SR_ERRORS) ? -1 : 0;
}

static void flash_unlock( void )
{
    if( FLASH_CR & CR_LOCK )
    {
        FLASH_KEYR = 0x45670123u;
        FLASH_KEYR = 0xCDEF89ABu;
    }
    FLASH_SR = SR_CLEAR;
}

/** The accelerator (ART) and the data cache hold what was there before: drop it, so that the next read sees the flash */
static void flash_refresh( uint32_t offset, uint32_t size )
{
    uint32_t acr = FLASH_ACR, a;

    FLASH_ACR = acr & ~(ACR_ICEN | ACR_DCEN);
    FLASH_ACR = (acr & ~(ACR_ICEN | ACR_DCEN)) | ACR_ICRST | ACR_DCRST;
    FLASH_ACR = acr;
    if( REG( 0xE000ED14u ) & (1u << 16) )       // CCR.DC: the data cache of the core is on (the firmware turned it on)
    {
        for( a = (0x08000000u + offset) & ~31u; a < 0x08000000u + offset + size; a += 32 )
        {
            REG( 0xE000EF5Cu ) = a;             // DCIMVAC
        }
        __asm volatile ( "dsb" ::: "memory" );
    }
    __asm volatile ( "isb" ::: "memory" );
}

static int allowed( uint32_t offset, uint32_t size )
{
    return offset >= DMSEL_F7_STORE_OFFSET && offset + size <= DMSEL_F7_STORE_OFFSET + DMSEL_F7_STORE_SIZE && offset + size >= offset;
}

int dmsel_f7_erase( void* user, uint32_t offset, uint32_t size )
{
    unsigned n;
    int result = 0;

    (void)user;
    if( !allowed( offset, size ) )
    {
        return -1;
    }
    flash_unlock();
    for( n = 0; n < 8 && result == 0; n++ )
    {
        if( g_sectors[n].offset >= offset && g_sectors[n].offset + g_sectors[n].size <= offset + size )
        {
            result = flash_wait();
            FLASH_CR = (FLASH_CR & ~(CR_SNB_MASK | CR_PSIZE_MASK)) | CR_PSIZE_X32 | CR_SER | (n << 3);
            FLASH_CR |= CR_STRT;
            result |= flash_wait();
            FLASH_CR &= ~(CR_SER | CR_SNB_MASK);
        }
    }
    FLASH_CR |= CR_LOCK;
    flash_refresh( offset, size );
    return result;
}

int dmsel_f7_program( void* user, uint32_t offset, const void* data, uint32_t size )
{
    const uint8_t* d = (const uint8_t*)data;
    uint32_t i;
    int result = 0;

    (void)user;
    if( (offset & 3u) != 0 || (size & 3u) != 0 || !allowed( offset, size ) )
    {
        return -1;
    }
    flash_unlock();
    FLASH_CR = (FLASH_CR & ~CR_PSIZE_MASK) | CR_PSIZE_X32;
    for( i = 0; i < size && result == 0; i += 4 )
    {
        uint32_t w = (uint32_t)d[i] | ((uint32_t)d[i + 1] << 8) | ((uint32_t)d[i + 2] << 16) | ((uint32_t)d[i + 3] << 24);
        result = flash_wait();
        FLASH_CR |= CR_PG;
        *(volatile uint32_t*)(0x08000000u + offset + i) = w;
        __asm volatile ( "dsb" ::: "memory" );
        result |= flash_wait();
        FLASH_CR &= ~CR_PG;
    }
    FLASH_CR |= CR_LOCK;
    flash_refresh( offset, size );
    return result;
}

void dmsel_f7_jump( void* user, uint32_t vector_address )
{
    const uint32_t* vectors = (const uint32_t*)vector_address;
    uint32_t sp = vectors[0], reset = vectors[1], i;

    (void)user;
    __asm volatile ( "cpsid i" ::: "memory" );
    REG( 0xE000E010u ) = 0;                     // SysTick off
    for( i = 0; i < 8; i++ )
    {
        REG( 0xE000E180u + 4 * i ) = 0xFFFFFFFFu;   // ICER
        REG( 0xE000E280u + 4 * i ) = 0xFFFFFFFFu;   // ICPR
    }
    REG( 0xE000ED08u ) = vector_address;        // VTOR
    __asm volatile ( "dsb\n isb\n msr msp, %0\n cpsie i\n bx %1" :: "r"(sp), "r"(reset) : "memory" );
    for( ;; ) {}
}

void dmsel_f7_watchdog_start( void* user, uint32_t timeout_ms )
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
