# Board configuration for LILYGO T-Deck Pro
# MCU: ESP32-S3 (QFN56, Xtensa LX7 dual-core, 240 MHz) with a 16 MB quad flash, USB = the USB-Serial/JTAG of the chip. The 8 MB of
# the board's external RAM are NOT the octal PSRAM of the ESP32-S3FN16R8 (its pads GPIO33-37 are the pins of the e-paper SPI)
set(TARGET "ESP32S3" CACHE STRING "Target microcontroller" FORCE)

# Layout of the flash and the selector: the same as on esp32s3-lcd28 (see its board.cmake for the description): both boards have a
# 16 MB flash
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

option(DMBOOT_ESP32S3_MODULES "ESP32-S3: the firmware with the modules (the packages must be built with DMOD_USE_RELDYN)" ON)
if(DMBOOT_ESP32S3_MODULES)
    set(DMBOOT_NO_FLASH_MODULES OFF CACHE BOOL "No modules in the firmware" FORCE)
else()
    set(DMBOOT_NO_FLASH_MODULES ON CACHE BOOL "No modules in the firmware" FORCE)
endif()

set(DMBOOT_BANK "A" CACHE STRING "Bank (A or B) that the image is linked for, started by the selector; empty: the whole flash, no selector")
set(DMBOOT_BANK_IMAGE_WINDOW 0x43000000)
set(DMBOOT_BANK_ONE_BUILD ON)
set(DMBOOT_SELECTOR_TABLE_ADDRESS 0x3fcd9700u)

# No external flash file system on this board yet (needs a dmflash configuration of the board)
set(DMBOOT_EXT_DEVICE "" CACHE STRING "Block device of the external flash; empty: the board has none (format-ext, upload-ext are not defined)")
