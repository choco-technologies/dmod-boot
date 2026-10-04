/**
 * @brief Cortex-M7 caches: enabled at boot, kept coherent for loaded modules
 *
 * The instruction and data caches are enabled before main() runs
 * (low_level_init_1(), called by startup.s after .data and .bss are set up).
 * Without them every access to the external SDRAM - where modules, their
 * heaps and framebuffers live - goes over the FMC bus, and code runs from
 * the flash with its wait states on every fetch.
 *
 * What other bus masters and the debugger see has to stay coherent:
 *  - the log ring buffer (.logs, read and written by the debugger through
 *    dmlog_monitor) is made non-cacheable with an MPU region - it is the
 *    first section of the RAM, so it is aligned for that;
 *  - the "dma" heap is the DTCM, which is never cached;
 *  - drivers that DMA into cacheable memory (dmsdio) or have it read by a
 *    peripheral (dmlcdtft and the LTDC) clean and invalidate by address;
 *  - the module loader calls Dmod_SyncCode() once a module is in place.
 */
#include "dmod.h"
#include <stdint.h>

#define SCB_CCR         (*(volatile uint32_t *)0xE000ED14UL)
#define SCB_CCR_DC      (1UL << 16)
#define SCB_CCR_IC      (1UL << 17)
#define SCB_CCSIDR      (*(volatile uint32_t *)0xE000ED80UL)
#define SCB_CSSELR      (*(volatile uint32_t *)0xE000ED84UL)
#define SCB_ICIALLU     (*(volatile uint32_t *)0xE000EF50UL)   /* invalidate the instruction cache */
#define SCB_DCISW       (*(volatile uint32_t *)0xE000EF60UL)   /* invalidate a data cache line by set/way */
#define SCB_DCCMVAU     (*(volatile uint32_t *)0xE000EF64UL)   /* clean a data cache line by address, to the point of unification */

#define MPU_TYPE        (*(volatile uint32_t *)0xE000ED90UL)
#define MPU_CTRL        (*(volatile uint32_t *)0xE000ED94UL)
#define MPU_RNR         (*(volatile uint32_t *)0xE000ED98UL)
#define MPU_RBAR        (*(volatile uint32_t *)0xE000ED9CUL)
#define MPU_RASR        (*(volatile uint32_t *)0xE000EDA0UL)

/* MPU region of the log buffer - dmfmc uses region 6 for the SDRAM; a
 * higher number wins where regions overlap, and these do not */
#define LOGS_MPU_REGION 7U

#define CACHE_LINE      32U

extern uint8_t __logs_start__[];
extern uint8_t __logs_end__[];

static inline void barriers(void)
{
    __asm volatile ("dsb" ::: "memory");
    __asm volatile ("isb" ::: "memory");
}

/* The log buffer non-cacheable: Normal memory, TEX=001 C=0 B=0, not
 * executable. An MPU region is a power of two of at least 32 bytes, aligned
 * to its size - false when the buffer is not like that. */
static bool logs_uncached(void)
{
    uintptr_t start = (uintptr_t)__logs_start__;
    uint32_t size = (uint32_t)(__logs_end__ - __logs_start__);
    if (MPU_TYPE == 0U || size < 32U || (size & (size - 1U)) != 0U || (start & (size - 1U)) != 0U)
        return false;

    uint32_t log2 = 0;
    while ((1UL << log2) < size)
        log2++;
    MPU_RNR  = LOGS_MPU_REGION;
    MPU_RBAR = (uint32_t)start;
    MPU_RASR = (1UL << 0)               /* ENABLE */
             | ((log2 - 1U) << 1)       /* SIZE: 2^(SIZE+1) bytes */
             | (1UL << 19)              /* TEX=001, C=0, B=0: Normal, non-cacheable */
             | (0x3UL << 24)            /* AP: read/write */
             | (1UL << 28);             /* XN */
    if ((MPU_CTRL & 0x1U) == 0U)
        MPU_CTRL |= (1UL << 0) | (1UL << 2);   /* ENABLE | PRIVDEFENA: the default map elsewhere */
    barriers();
    return true;
}

static void enable_icache(void)
{
    barriers();
    SCB_ICIALLU = 0U;
    barriers();
    SCB_CCR |= SCB_CCR_IC;
    barriers();
}

static void enable_dcache(void)
{
    SCB_CSSELR = 0U;                    /* Level 1 data cache */
    barriers();
    uint32_t ccsidr = SCB_CCSIDR;
    uint32_t sets = ((ccsidr >> 13) & 0x7FFFU) + 1U;
    uint32_t ways = ((ccsidr >> 3) & 0x3FFU) + 1U;
    for (uint32_t set = 0; set < sets; set++)
    {
        for (uint32_t way = 0; way < ways; way++)
            SCB_DCISW = (way << 30) | (set << 5);
    }
    barriers();
    SCB_CCR |= SCB_CCR_DC;
    barriers();
}

/* Called by startup.s before main() */
void low_level_init_1(void)
{
    enable_icache();
    if (logs_uncached())
        enable_dcache();                /* Else the debugger would not see the logs */
}

/* See dmod_sal.h: the code just written reaches the instruction fetch */
void Dmod_SyncCode(const void* Address, size_t Size)
{
    if (Address == NULL || Size == 0U)
        return;
    if ((SCB_CCR & SCB_CCR_DC) != 0U)
    {
        uintptr_t line = (uintptr_t)Address & ~(uintptr_t)(CACHE_LINE - 1U);
        uintptr_t end = (uintptr_t)Address + Size;
        __asm volatile ("dsb" ::: "memory");
        for (; line < end; line += CACHE_LINE)
            SCB_DCCMVAU = (uint32_t)line;
    }
    if ((SCB_CCR & SCB_CCR_IC) != 0U)
    {
        __asm volatile ("dsb" ::: "memory");
        SCB_ICIALLU = 0U;
    }
    barriers();
}
