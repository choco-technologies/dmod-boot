/*
 * dmboot on the ESP32-S3 as the image of a bank of the selector (selector/, docs/esp32s3-selector.md): XIP.
 *
 * The selector maps the pages of the bank into a window of the instruction bus (0x43000000) and of the data bus (0x3D000000,
 * the same pages): the code is linked for the first, the read-only data for the second (the instruction bus cannot read
 * bytes), both in the image of the bank right after its 512 bytes of the header (DMBOOT_ROM_ORIGIN, DMBOOT_ROM_LENGTH
 * come from --defsym). The vectors of the exceptions and the code that has to run when the flash cannot be read are copied
 * to the IRAM by the start. The RAM stays below the RAM of the selector (0x3fcd1700 and up: its code, its data and its table).
 *
 *   IRAM 0x40378000 .. 0x40380000   vectors, code of the interrupts (the data bus sees it at 0x3fc88000)
 *   RAM  0x3fc90000 .. 0x3fcc8000   the log, the data, the stack, the heap
 *   DMA  0x3fcc8000 .. 0x3fcd0000   the heap of the DMA
 *   (0x3fcda000 .. 0x3fce9700: what the selector used only for its start; the buffers of the radio are there - dmespwifi)
 */
MEMORY
{
    rom     (rx)  : ORIGIN = DMBOOT_ROM_ORIGIN, LENGTH = DMBOOT_ROM_LENGTH
    iram    (rx)  : ORIGIN = 0x40378000, LENGTH = 0x8000
    ram     (rwx) : ORIGIN = 0x3fc90000, LENGTH = 0x38000
    dma     (rwx) : ORIGIN = 0x3fcc8000, LENGTH = 0x8000
    ext     (rwx) : ORIGIN = 0x3f800000, LENGTH = 0          /* the PSRAM: not used yet */
}

/* The ROM (the same on every chip; components/esp_rom/esp32s3/ld/esp32s3.rom.ld of ESP-IDF) */
ets_printf                      = 0x400005d0;
esp_rom_printf                  = 0x400005d0;
ets_delay_us                    = 0x40000600;
ets_get_cpu_frequency           = 0x40001a40;
_xtos_set_intlevel              = 0x40001c38;
