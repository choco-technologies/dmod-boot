#include <stdint.h>
extern uint32_t _estack, _sbss, _ebss;
int main( void );
void Default_Handler( void ) { for( ;; ) {} }
void Reset_Handler( void )
{
    for( uint32_t* p = &_sbss; p < &_ebss; ) *p++ = 0;
    main();
    for( ;; ) {}
}
__attribute__(( section( ".isr_vector" ), used ))
const void* const g_vectors[16] = { &_estack, Reset_Handler, Default_Handler, Default_Handler, Default_Handler, Default_Handler,
    Default_Handler, 0, 0, 0, 0, Default_Handler, Default_Handler, 0, Default_Handler, Default_Handler };
