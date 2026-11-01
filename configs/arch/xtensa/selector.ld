/* The selector (selector/): Xtensa - the entry is _start (selector/arch/xtensa/startup.c), the stack grows down from the end of
   the data RAM (DMSEL_STACK_SIZE: selector/linker/ram.ld) */
ENTRY(_start)
OUTPUT_FORMAT("elf32-xtensa-le")
