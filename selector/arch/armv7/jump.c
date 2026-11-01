/**
 * @file jump.c
 * @brief ARMv7-M: the jump into an image - the core quiet, the vector table of the image, its stack and its reset handler
 */
#include <stdint.h>
#include "dmsel_platform.h"

#define REG(a)          (*(volatile uint32_t*)(a))

void dmsel_arch_jump( void* user, uint32_t vector_address )
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
