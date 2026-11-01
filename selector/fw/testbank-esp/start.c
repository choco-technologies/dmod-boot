/**
 * @file start.c
 * @brief The entry of the test firmware (offset 0x200 of the image): the windows of the registers, the stack, the data in the
 *        RAM, then main()
 *
 * The first instruction of the image is the entry (the selector jumps to the header area + 512) and a jump is a relative
 * instruction, it needs no literal; the code with the literals follows.
 */
#include <stdint.h>

extern uint32_t _sdata, _edata, _data_load, _siram, _eiram, _iram_load, _sbss, _ebss;
int main( void );

#define CODE_TO_DATA_WINDOW     0x06000000u         // 0x43000000 - 0x3D000000: the data bus reads the image in bytes
#define IRAM_TO_DRAM            0x6f0000u

__asm__(
    "   .section .entry.text, \"ax\"\n"
    "   .global _start\n"
    "   .type   _start, @function\n"
    "_start:\n"
    "   j       _start2\n"
    "   .size   _start, . - _start\n"
    "   .section .entry2.text, \"ax\"\n"
    "   .align  4\n"
    "   .literal_position\n"
    "_start2:\n"
    "   movi    a0, 0\n"
    "   wsr.windowbase a0\n"
    "   movi    a0, 1\n"
    "   wsr.windowstart a0\n"
    "   rsync\n"
    "   movi    a0, 0\n"
    "   wsr.intenable a0\n"
    "   movi    a1, _stack_top\n"
    "   movi    a2, 0x40020\n"                          // PS: WOE | UM
    "   wsr.ps  a2\n"
    "   rsync\n"
    "   movi    a4, fw_start\n"
    "   callx4  a4\n"
    "1: j       1b\n"
);

__attribute__(( optimize( "no-tree-loop-distribute-patterns" ), noreturn, used ))
void fw_start( void )
{
    const uint32_t* src = (const uint32_t*)((uint32_t)&_data_load - CODE_TO_DATA_WINDOW);
    uint32_t* dst;

    for( dst = &_sdata; dst < &_edata; ) *dst++ = *src++;
    src = (const uint32_t*)((uint32_t)&_iram_load - CODE_TO_DATA_WINDOW);
    for( dst = (uint32_t*)((uint32_t)&_siram - IRAM_TO_DRAM); dst < (uint32_t*)((uint32_t)&_eiram - IRAM_TO_DRAM); ) *dst++ = *src++;
    __asm volatile ( "memw\n isync" ::: "memory" );
    for( dst = &_sbss; dst < &_ebss; ) *dst++ = 0;
    main();
    for( ;; ) {}
}
