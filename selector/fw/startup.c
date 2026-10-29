/**
 * @file startup.c
 * @brief Vectors and the reset handler of the selector: the RAM is the DTCM, nothing else runs here
 */
#include <stdint.h>

extern uint32_t _estack, _sidata, _sdata, _edata, _sbss, _ebss;
int main( void );

void Default_Handler( void )
{
    for( ;; ) {}
}

void Reset_Handler( void )
{
    uint32_t *src = &_sidata, *dst;

    for( dst = &_sdata; dst < &_edata; ) *dst++ = *src++;
    for( dst = &_sbss; dst < &_ebss; ) *dst++ = 0;
    main();
    for( ;; ) { __asm volatile ( "wfi" ); }
}

void NMI_Handler( void )        __attribute__(( weak, alias( "Default_Handler" ) ));
void HardFault_Handler( void )  __attribute__(( weak, alias( "Default_Handler" ) ));

__attribute__(( section( ".isr_vector" ), used ))
const void* const g_vectors[16] =
{
    &_estack, Reset_Handler, NMI_Handler, HardFault_Handler,
    Default_Handler, Default_Handler, Default_Handler, 0, 0, 0, 0,
    Default_Handler, Default_Handler, 0, Default_Handler, Default_Handler,
};
