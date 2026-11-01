/* The selector that runs from the RAM (the ROM loads the image there: ESP32-S3). The code is in IRAM, the table, the data
   and the stack in DRAM; the memory map is the mcu's (selector.ld), the entry the arch's. Every section is loaded
   (the ROM copies the segments of the image), only the bss is cleared by the selector. */
DMSEL_STACK_SIZE = 0x2000;                  /* 8 kB of the stack at the end of the DRAM */

SECTIONS
{
    .iram.text : ALIGN(16)
    {
        KEEP(*(.entry.literal .entry.text))
        *(.literal .literal.* .text .text.*)
        . = ALIGN(16);
    } > IRAM

    /* the table of the firmware is at the start of the DRAM, a fixed place (DMSEL_TABLE_ADDRESS) */
    .dmsel_table : ALIGN(16) { KEEP(*(.dmsel_table)) } > DRAM
    .dram.rodata : ALIGN(16) { *(.rodata .rodata.*) *(.srodata .srodata.*) . = ALIGN(4); } > DRAM
    .dram.data : ALIGN(16) { *(.data .data.*) *(.sdata .sdata.*) . = ALIGN(4); } > DRAM
    .dram.bss (NOLOAD) : ALIGN(16)
    {
        _sbss = .;
        *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
        . = ALIGN(16);
        _ebss = .;
    } > DRAM
    _stack_top = ORIGIN(DRAM) + LENGTH(DRAM);
    ASSERT(_ebss + DMSEL_STACK_SIZE <= _stack_top, "the selector: the data and the stack do not fit in the DRAM")

    /DISCARD/ : { *(.comment) *(.inputs) *(.dmod*) *(.xt.*) *(.xtensa.info) *(.note.*) }
}
