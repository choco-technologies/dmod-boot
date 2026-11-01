/* The selector: the code and the table in the FLASH, the stack and the (uninitialized) data in the RAM.
   The memory map is the mcu's (mcu.ld), the entry and the top of the stack the arch's (arch.ld). */
DMSEL_STACK_SIZE = 0x1000;                  /* 4 kB of the stack at the bottom of the RAM, the data above it */

SECTIONS
{
    .isr_vector : { KEEP(*(.isr_vector)) } > FLASH
    .dmsel_table ORIGIN(FLASH) + 0x100 : { KEEP(*(.dmsel_table)) } > FLASH   /* DMSEL_TABLE_ADDRESS */
    .text : { *(.text .text.*) *(.rodata .rodata.*) . = ALIGN(4); } > FLASH
    _sidata = LOADADDR(.data);
    .data ORIGIN(RAM) + DMSEL_STACK_SIZE : { _sdata = .; *(.data .data.*) . = ALIGN(4); _edata = .; } > RAM AT > FLASH
    .bss ORIGIN(RAM) + DMSEL_STACK_SIZE (NOLOAD) : { _sbss = .; *(.bss .bss.*) *(COMMON) . = ALIGN(4); _ebss = .; } > RAM
    /DISCARD/ : { *(.ARM.exidx*) *(.comment) *(.inputs) *(.dmod*) }
}
ASSERT(SIZEOF(.data) == 0, "the selector has no initialized RAM: keep it const")
