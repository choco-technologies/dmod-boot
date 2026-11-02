# Board configuration for the ESP32-S3 2.8" display development board (240x320 IPS)
# MCU: ESP32-S3 (Xtensa LX7 dual-core, 240 MHz, 16 MB flash, 8 MB PSRAM), the USB port is the chip's USB-Serial/JTAG
set(TARGET "ESP32S3" CACHE STRING "Target microcontroller" FORCE)

# Layout of the flash (selector/). The flash is seen by the data bus from 0x3C000000 (the selector maps all of it), so the
# origins below are addresses on that bus: the offset in the flash is the address minus the origin of the selector. The
# selector is the second stage bootloader (the image at offset 0 of the flash, loaded by the ROM into the RAM); the MMU
# pages are 64 kB, so everything starts at a multiple of 64 kB.
#
#   0x000000  64 kB    the selector (the image with its header)
#   0x010000  64 kB    its store (32 kB of it used: the state of the banks, the persistent items)
#   0x020000  896 kB   free
#   0x100000  3 MB     slot of the bank A: the image 0x2F0000, then the file system of the bank (/) 64 kB
#   0x400000  3 MB     slot of the bank B, the same
#   0x700000  9 MB     /ext (littlefs, common to both banks)
#
# The file system of a bank is writable and belongs to the bank (a new firmware in one bank does not touch the files of the
# other one): the selector does not use it, a plugin of the firmware does (dmflash, a port for the ESP32-S3). The selector
# knows the bank as its image only (DMBOOT_BANK_x_SIZE), so writing an image never reaches the file system.
set(DMBOOT_BANK_A_ORIGIN    0x3C100000)
set(DMBOOT_BANK_A_SIZE      0x002F0000)
set(DMBOOT_BANK_A_FS_ORIGIN 0x3C3F0000)
set(DMBOOT_BANK_A_FS_SIZE   0x00010000)
set(DMBOOT_BANK_B_ORIGIN    0x3C400000)
set(DMBOOT_BANK_B_SIZE      0x002F0000)
set(DMBOOT_BANK_B_FS_ORIGIN 0x3C6F0000)
set(DMBOOT_BANK_B_FS_SIZE   0x00010000)
set(DMBOOT_EXT_ORIGIN       0x3C700000)
set(DMBOOT_EXT_SIZE         0x00900000)
set(DMBOOT_SELECTOR_ORIGIN 0x3C000000)
set(DMBOOT_SELECTOR_STORE  0x3C010000)
set(DMBOOT_SELECTOR_STORE_SIZE 0x00008000)

# The modules of the Xtensa run: dmod relocates them by a table (DMOD_USE_RELDYN, dmod: docs/reldyn.md) and runs them from the alias
# of the RAM on the instruction bus. -DDMBOOT_ESP32S3_MODULES=OFF builds the firmware alone.
option(DMBOOT_ESP32S3_MODULES "ESP32-S3: the firmware with the modules (the packages must be built with DMOD_USE_RELDYN)" ON)
if(DMBOOT_ESP32S3_MODULES)
    set(DMBOOT_NO_FLASH_MODULES OFF CACHE BOOL "No modules in the firmware" FORCE)
else()
    set(DMBOOT_NO_FLASH_MODULES ON CACHE BOOL "No modules in the firmware" FORCE)
endif()

# The image of a bank (dmboot): one build for both banks, linked for the window that the selector maps the bank into (the code
# bus; the data bus sees the same pages at 0x3D000000), started as the bank A by default
set(DMBOOT_BANK "A" CACHE STRING "Bank (A or B) that the image is linked for, started by the selector; empty: the whole flash, no selector")
set(DMBOOT_BANK_IMAGE_WINDOW 0x43000000)
set(DMBOOT_BANK_ONE_BUILD ON)
set(DMBOOT_SELECTOR_TABLE_ADDRESS 0x3fcd9700u)
