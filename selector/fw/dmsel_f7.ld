/* The selector: the first sector of the flash (32 kB), the DTCM for the RAM */
MEMORY
{
    FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 32K
    DTCM  (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}
ENTRY(Reset_Handler)
_estack = ORIGIN(DTCM) + 0x1000;            /* 4 kB of the stack at the bottom of the DTCM, the data above it */

SECTIONS
{
    .isr_vector : { KEEP(*(.isr_vector)) } > FLASH
    .dmsel_table ORIGIN(FLASH) + 0x100 : { KEEP(*(.dmsel_table)) } > FLASH   /* DMSEL_TABLE_ADDRESS */
    .text : { *(.text .text.*) *(.rodata .rodata.*) . = ALIGN(4); } > FLASH
    _sidata = LOADADDR(.data);
    .data ORIGIN(DTCM) + 0x1000 : { _sdata = .; *(.data .data.*) . = ALIGN(4); _edata = .; } > DTCM AT > FLASH
    .bss ORIGIN(DTCM) + 0x1000 (NOLOAD) : { _sbss = .; *(.bss .bss.*) *(COMMON) . = ALIGN(4); _ebss = .; } > DTCM
    /DISCARD/ : { *(.ARM.exidx*) *(.comment) *(.inputs) *(.dmod*) }
}
ASSERT(SIZEOF(.data) == 0, "the selector has no initialized RAM: keep it const")
