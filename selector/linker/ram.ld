/* The selector that runs from the RAM (the ROM loads the image there: ESP32-S3). The code is in IRAM, the table and the data in DRAM,
   the buffers of the start and the stack in BOOT; the memory map is the mcu's (selector.ld), the entry the arch's. Every section is loaded
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
    /* What only the start needs - the scratch of the store and the log (fw/main.c), the stack - is in a region of its own (BOOT, after the
       DRAM), which the firmware may take: the calls through the table use the memory of the firmware, and of the selector only what stays
       in the DRAM. (This statement is before .dram.bss so that the two buffers are not taken by its pattern.) */
    .boot.bss (NOLOAD) : ALIGN(16)
    {
        *(.bss.g_scratch .bss.g_log_storage)
        . = ALIGN(16);
        _ebss = .;
    } > BOOT
    .dram.bss (NOLOAD) : ALIGN(16)
    {
        _sbss = .;
        *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
        . = ALIGN(16);
    } > DRAM
    /* (the start clears from _sbss to _ebss: the bss of the DRAM, the rest of the DRAM and the buffers of BOOT) */
    ASSERT(ORIGIN(DRAM) + LENGTH(DRAM) == ORIGIN(BOOT), "the selector: BOOT must follow the DRAM")
    _stack_top = ORIGIN(BOOT) + LENGTH(BOOT);
    ASSERT(_ebss + DMSEL_STACK_SIZE <= _stack_top, "the selector: the buffers and the stack do not fit in BOOT")

    /DISCARD/ : { *(.comment) *(.inputs) *(.dmod*) *(.xt.*) *(.xtensa.info) *(.note.*) }
}
