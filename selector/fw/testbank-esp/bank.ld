/* A test image of a bank for the ESP32-S3: one build for both banks, XIP (the selector maps the pages of the bank to
   0x43000000 for the code bus; the same pages are 0x3D000000 for the data bus).
   The image of the bank, as the selector makes it (dmsel_mkimage.py): 512 bytes of the header, then the bytes of the code.
   The code bus cannot read bytes, so the read-only data are linked for the data window, but they lie in the image right
   after the code (the load address is in the code window: objcopy makes the image by the load addresses). The data and
   the code that has to run from the RAM follow, and the start of the firmware copies them. */
IMAGE_CODE  = 0x43000000;
IMAGE_DATA  = 0x3D000000;
MEMORY
{
    IMG   (rx)  : ORIGIN = 0x43000200, LENGTH = 0x2EFE00        /* the bank without its header area */
    IRAM  (rx)  : ORIGIN = 0x40378000, LENGTH = 0x8000          /* the instruction bus of 0x3fc88000 */
    DRAM  (rw)  : ORIGIN = 0x3fc90000, LENGTH = 0x40000         /* ends before the RAM of the selector (0x3fcd1700..) */
}
iram_dram_offset = 0x6f0000;                /* 0x40378000 - 0x3fc88000 */
ets_delay_us = 0x40000600;                  /* the ROM */

ENTRY(_start)
SECTIONS
{
    .text : ALIGN(4)
    {
        KEEP(*(.entry.text))                /* at the entry of the image: offset 0x200 */
        KEEP(*(.entry2.text))
        *(.literal .literal.* .text .text.*)
        . = ALIGN(16);
    } > IMG
    _rodata_load = .;
    .rodata (_rodata_load - IMAGE_CODE + IMAGE_DATA) : AT(_rodata_load)
    {
        *(.rodata .rodata.*) *(.srodata .srodata.*)
        . = ALIGN(16);
    }
    _data_load = LOADADDR(.rodata) + SIZEOF(.rodata);
    .data : AT(_data_load)
    {
        _sdata = .; *(.data .data.*) *(.sdata .sdata.*) . = ALIGN(4); _edata = .;
    } > DRAM
    _iram_load = _data_load + SIZEOF(.data);
    .iram.text : AT(_iram_load)
    {
        _siram = .; *(.iram.text .iram.text.*) . = ALIGN(4); _eiram = .;
    } > IRAM
    .bss (NOLOAD) : ALIGN(16)
    {
        _sbss = .; *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON) . = ALIGN(16); _ebss = .;
    } > DRAM
    _stack_top = ORIGIN(DRAM) + LENGTH(DRAM);
    ASSERT(_ebss + 0x2000 <= _stack_top, "the test firmware: the data and the stack do not fit in the RAM")
    /DISCARD/ : { *(.comment) *(.xt.*) *(.xtensa.info) *(.note.*) }
}
