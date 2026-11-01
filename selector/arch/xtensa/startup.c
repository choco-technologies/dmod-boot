/**
 * @file startup.c
 * @brief Xtensa LX: the entry of the selector (the ROM jumps here after it has loaded the image) - the windows of the registers,
 *        the stack, the bss (the RAM and the stack: mcu selector.ld, ram.ld)
 *
 * The code is the windowed ABI, as the ROM's: the window overflow and underflow handlers that the ROM leaves in the vectors
 * (VECBASE is not touched) spill the frames onto the stack set here. Nothing here uses an interrupt.
 */
#include <stdint.h>

extern uint32_t _sbss, _ebss;
int main( void );

__asm__(
    "   .section .entry.text, \"ax\"\n"
    "   .align  4\n"
    "   .literal_position\n"
    "   .global _start\n"
    "   .type   _start, @function\n"
    "_start:\n"
    "   movi    a0, 0\n"
    "   wsr.windowbase a0\n"
    "   movi    a0, 1\n"
    "   wsr.windowstart a0\n"
    "   rsync\n"
    "   movi    a0, 0\n"
    "   wsr.intenable a0\n"
    "   movi    a1, _stack_top\n"
    "   movi    a2, 0x40020\n"                          // PS: WOE (windows on) | UM (user vector mode), INTLEVEL 0
    "   wsr.ps  a2\n"
    "   rsync\n"
    "   movi    a4, dmsel_start\n"
    "   callx4  a4\n"
    "1: j       1b\n"
    "   .size   _start, . - _start\n"
);

__attribute__(( optimize( "no-tree-loop-distribute-patterns" ), noreturn, used ))
void dmsel_start( void )
{
    uint32_t* dst;

    for( dst = &_sbss; dst < &_ebss; ) *dst++ = 0;
    main();
    for( ;; ) {}
}
