/**
 * @file jump.c
 * @brief Xtensa LX: the jump into an image and the idle of the core
 *
 * The address is already one the code can be fetched from: the mcu has brought the image into the memory of the chip
 * (dmsel_mcu_prepare_jump: the MMU, the instruction cache).
 */
#include <stdint.h>
#include "dmsel_platform.h"

void dmsel_arch_jump( void* user, uint32_t entry_address )
{
    uint32_t ps;

    (void)user;
    __asm volatile ( "rsil %0, 15\n wsr.intenable %1\n isync\n jx %2"
                     : "=&a"(ps) : "a"(0), "a"(entry_address) : "memory" );
    for( ;; ) {}
}

void dmsel_arch_idle( void )
{
    __asm volatile ( "waiti 0" ::: "memory" );
}
