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
#   0x020000  896 kB   the image of the Wi-Fi libraries (dmespwifi: 260 kB, executed in place), written by install-firmware
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
# The Wi-Fi of the chip (dmespwifi): the image of the Espressif libraries is linked for fixed addresses - its code in the flash from 0x020000, its
# .data/.bss in the last 16 kB of the RAM, which the firmware leaves alone (mcu.ld). The buffers of the radio are in the RAM that the selector
# needs only for its start (selector.ld: BOOT)
set(DMBOOT_RESERVED_RAM 0x4000 CACHE STRING "Bytes at the end of the RAM that the firmware does not use" FORCE)
set(DMBOOT_ESP_WIFI_IMAGE_OFFSET 0x020000 CACHE STRING "Offset in the flash of the image of the Wi-Fi libraries (dmespwifi); empty: none" FORCE)
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

# The external flash (/ext): the last 9 MB of the flash of the chip, a littlefs on the block node of dmflash (flash.dmd, services/ext.ini).
# format-ext creates the file system, upload-ext sends build/ext over the console (YMODEM).
set(DMBOOT_EXT_DEVICE "/dev/dmflashx/ext" CACHE STRING "Block device of the external flash; empty: the board has none (format-ext, upload-ext are not defined)")
# The default vault of dmsecrets (wifid waits for the file to appear)
set(DMBOOT_DMSECRETS_PATH "/ext/secrets.vault" CACHE STRING "Path of the default dmsecrets vault (DMSECRETS_PATH at boot); empty: not set")
set(DMBOOT_EXT_FS "dmlittlefs" CACHE STRING "File system of the external flash")
set(DMBOOT_EXT_MKFS "mklittlefs" CACHE STRING "Command that creates it on the device (format-ext)")
set(DMBOOT_EXT_MOUNT "/ext" CACHE STRING "Where the external flash is mounted")

# Splash logo the display driver (dmst7789) shows on the 240x320 panel as soon as it is up (an asset of assets/splash/, see
# DMBOOT_SPLASH_LOGO). It is built into the firmware (/eviews/splash_logo.dmvir): the display driver is a module of the firmware. The
# logo is 150x128 and takes 57 kB of the 3 MB of the bank.
set(DMBOOT_SPLASH_LOGO "dmodos_logo_128" CACHE STRING "Splash logo the display driver shows at start")
