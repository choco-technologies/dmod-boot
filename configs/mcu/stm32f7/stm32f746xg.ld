MEMORY
{
    rom     (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
    ram     (rwx) : ORIGIN = 0x20010000, LENGTH = 256K
    ext     (rwx) : ORIGIN = 0x60000000, LENGTH = 2047M
    dma     (rwx) : ORIGIN = 0x20000000, LENGTH = 64k
}

/* Define symbols for memory regions specific for this target */
PROVIDE(__dtcm_start__ = 0x20000000);
PROVIDE(__dtcm_size__  = 64K);
PROVIDE(__dtcm_end__   = __dtcm_start__ + __dtcm_size__);

PROVIDE(__sram1_start__ = 0x20010000);
PROVIDE(__sram1_size__  = 240K);
PROVIDE(__sram1_end__   = __sram1_start__ + __sram1_size__);

PROVIDE(__sram2_start__ = 0x20040000);
PROVIDE(__sram2_size__  = 16K);
PROVIDE(__sram2_end__   = __sram2_start__ + __sram2_size__);