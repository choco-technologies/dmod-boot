/**
 * @brief ARMv7-M system reset for Cortex-M4/M7.
 */
#include "dmod.h"
#include <stdint.h>

int Dmod_Reboot(void)
{
    volatile uint32_t* const aircr = (volatile uint32_t*)0xE000ED0CUL;
    const uint32_t vectkey = 0x5FAUL << 16;
    const uint32_t prigroup_mask = 7UL << 8;
    const uint32_t sysresetreq = 1UL << 2;

    __asm volatile ("cpsid i" ::: "memory");
    __asm volatile ("dsb sy" ::: "memory");
    // Preserve interrupt priority grouping and supply the AIRCR write key.
    *aircr = vectkey | (*aircr & prigroup_mask) | sysresetreq;
    __asm volatile ("dsb sy" ::: "memory");
    for(;;)
    {
        __asm volatile ("nop");
    }
}
