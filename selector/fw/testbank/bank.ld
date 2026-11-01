/* A test image of a bank; BANK_ORIGIN (the vectors: the start of the bank + 0x200) comes from --defsym */
MEMORY
{
    FLASH (rx)  : ORIGIN = BANK_ORIGIN, LENGTH = 0x5FE00
    RAM   (rwx) : ORIGIN = 0x20010000, LENGTH = 0x3C000
}
_estack = 0x2004C000;
ENTRY(Reset_Handler)
SECTIONS
{
    .isr_vector : { KEEP(*(.isr_vector)) } > FLASH
    .text : { *(.text .text.*) *(.rodata .rodata.*) . = ALIGN(4); } > FLASH
    .result 0x20010000 (NOLOAD) : { KEEP(*(.result)) } > RAM
    .cmd    0x20010100 (NOLOAD) : { KEEP(*(.cmd)) } > RAM
    .bss 0x20010200 (NOLOAD) : { _sbss = .; *(.bss .bss.*) . = ALIGN(4); _ebss = .; } > RAM
    /DISCARD/ : { *(.ARM.exidx*) *(.comment) }
}
