/*
 * ESP32-S3FN16R8 memory layout (bare-metal / direct OpenOCD load):
 *
 *  IRAM (instruction RAM, no cache needed):
 *    0x40374000 – 0x403BFFFF  320 KB  – application code executed directly
 *
 *  DRAM (data RAM, internal SRAM1 as data):
 *    0x3FC88000 – 0x3FCEFFFF  416 KB  – application data / BSS / stack / heap
 *
 *  External flash (SPI, 16 MB) – available after cache is enabled:
 *    IROM (instruction): 0x42000000 + offset
 *    DROM (read-only data): 0x3C000000 + offset
 *
 * For development (direct OpenOCD load without the ROM bootloader cache
 * setup), all code and data are placed in the internal IRAM / DRAM regions
 * so that the firmware runs without any cache initialisation.
 */

MEMORY
{
    rom  (rx)  : ORIGIN = 0x40374000, LENGTH = 320K
    ram  (rwx) : ORIGIN = 0x3FC88000, LENGTH = 416K
    ext  (rwx) : ORIGIN = 0x3C000000, LENGTH = 0
    dma  (rwx) : ORIGIN = 0x3FC88000, LENGTH = 0
}
