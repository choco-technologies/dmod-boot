/**
 * @file caches.c
 * @brief Dmod_SyncCode() of the ESP32-S3: the code of a module in the external RAM
 *
 * The external RAM is reached through the cache of the CPU: the data bus (0x3C000000..0x3E000000) writes it through the data cache
 * (write-back), the instruction bus (the same window, 0x6000000 higher) fetches it through the instruction cache. What the module
 * loader has written must be in the RAM, not in the data cache, and the instruction cache must not hold the lines of the memory
 * that the module is loaded into (what was there before) when the module is executed. The internal RAM has no cache.
 *
 * It is the chip's (the functions are the ESP32-S3's ROM), so it is here and not in dmod, which knows the Xtensa only. It replaces
 * the weak Dmod_SyncCode() of dmod, as the Cortex-M7 caches do. Only the ROM functions are used: it runs while the module is
 * loaded, with the caches working.
 */
#include <stddef.h>
#include <stdint.h>

#define CACHE_WINDOW_LOW        0x3C000000UL
#define CACHE_WINDOW_HIGH       0x3E000000UL
#define CACHE_CODE_OFFSET       0x06000000UL    /* the window of the data bus -> the instruction bus */

/* ROM (esp32s3.rom.ld) */
#define ROM_CACHE_GET_ICACHE_LINE_SIZE      0x400015fcUL    /* uint32_t (void) */
#define ROM_CACHE_INVALIDATE_ICACHE_ITEMS   0x40001674UL    /* void (uint32_t addr, uint32_t items), addr of the instruction bus */
#define ROM_CACHE_WRITEBACK_ALL             0x400016f8UL    /* void (void) */
#define ROM_CACHE_SUSPEND_DCACHE_AUTOLOAD   0x40001734UL    /* uint32_t (void) */
#define ROM_CACHE_RESUME_DCACHE_AUTOLOAD    0x40001740UL    /* void (uint32_t) */

/* See dmod_sal.h: the code just written reaches the instruction fetch */
void Dmod_SyncCode(const void* Address, size_t Size)
{
    uintptr_t start = (uintptr_t)Address;
    uintptr_t end = start + Size;

    /* The stores are done (memw) */
    __asm__ __volatile__("memw" ::: "memory");

    if (Size != 0U && end > CACHE_WINDOW_LOW && start < CACHE_WINDOW_HIGH)
    {
        /* The data cache holds the new code: into the RAM with it. The autoload (prefetch) is suspended meanwhile, so no line is
           loaded while the lines are written back. */
        uint32_t autoload = ( (uint32_t (*)( void ))ROM_CACHE_SUSPEND_DCACHE_AUTOLOAD )();
        ( (void (*)( void ))ROM_CACHE_WRITEBACK_ALL )();
        ( (void (*)( uint32_t ))ROM_CACHE_RESUME_DCACHE_AUTOLOAD )( autoload );

        /* The instruction cache must fetch the lines from the RAM again: it may hold what was there before */
        uintptr_t line = ( (uint32_t (*)( void ))ROM_CACHE_GET_ICACHE_LINE_SIZE )();
        uintptr_t first = start & ~( line - 1U );
        uintptr_t items = ( end - first + line - 1U ) / line;
        ( (void (*)( uint32_t, uint32_t ))ROM_CACHE_INVALIDATE_ICACHE_ITEMS )( (uint32_t)( first + CACHE_CODE_OFFSET ), (uint32_t)items );
    }

    /* What the processor has fetched already is dropped (isync) */
    __asm__ __volatile__("isync" ::: "memory");
}
