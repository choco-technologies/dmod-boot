# Board configuration for the Elecrow DIS08070H (CrowPanel ESP32 HMI 7.0": 800x480 RGB TFT, capacitive touch GT911)
# MCU: ESP32-S3-WROOM-1-N4R8 (Xtensa LX7 dual-core, 240 MHz, 4 MB quad flash, 8 MB octal PSRAM). The USB-C connector is a USB-UART bridge
# on UART0 (GPIO43 TX / GPIO44 RX; /dev/ttyUSB0 on the host) - the USB-Serial/JTAG of the chip is not wired to a connector, so there is no
# JTAG: the board is flashed with esptool over the UART (the ROM bootloader), and the log of the selector is not on the console.
set(TARGET "ESP32S3" CACHE STRING "Target microcontroller" FORCE)

# The chip is the same family as on esp32s3-lcd28 (see its board.cmake for the description of the layout), but the flash is 4 MB, not 16 MB:
# the selector (the ROM's SPI driver, the MMU) and the firmware (/ext) have to know it.
set(DMBOOT_FLASH_SIZE       0x00400000)

# Layout of the flash (every item starts at a multiple of 64 kB, the page of the MMU):
#
#   0x000000  64 kB    the selector (the image with its header)
#   0x010000  64 kB    its store (32 kB of it used)
#   0x020000  960 kB   slot of the bank A: the image 0xF0000 (the firmware with the modules built in), then the file system of the bank 64 kB
#   0x120000  960 kB   slot of the bank B, the same
#   0x220000  1.9 MB   /ext (littlefs, common to both banks)
set(DMBOOT_BANK_A_ORIGIN    0x3C020000)
set(DMBOOT_BANK_A_SIZE      0x000F0000)
set(DMBOOT_BANK_A_FS_ORIGIN 0x3C110000)
set(DMBOOT_BANK_A_FS_SIZE   0x00010000)
set(DMBOOT_BANK_B_ORIGIN    0x3C120000)
set(DMBOOT_BANK_B_SIZE      0x000F0000)
set(DMBOOT_BANK_B_FS_ORIGIN 0x3C210000)
set(DMBOOT_BANK_B_FS_SIZE   0x00010000)
set(DMBOOT_EXT_ORIGIN       0x3C220000)
set(DMBOOT_EXT_SIZE         0x001E0000)
set(DMBOOT_SELECTOR_ORIGIN 0x3C000000)
set(DMBOOT_SELECTOR_STORE  0x3C010000)
set(DMBOOT_SELECTOR_STORE_SIZE 0x00008000)
set(DMBOOT_SELECTOR_TABLE_ADDRESS 0x3fcd9700u)

# The modules of the Xtensa run: dmod relocates them by a table (DMOD_USE_RELDYN) and runs them from the alias of the RAM on the
# instruction bus. -DDMBOOT_ESP32S3_MODULES=OFF builds the firmware alone.
option(DMBOOT_ESP32S3_MODULES "ESP32-S3: the firmware with the modules (the packages must be built with DMOD_USE_RELDYN)" ON)
if(DMBOOT_ESP32S3_MODULES)
    set(DMBOOT_NO_FLASH_MODULES OFF CACHE BOOL "No modules in the firmware" FORCE)
else()
    set(DMBOOT_NO_FLASH_MODULES ON CACHE BOOL "No modules in the firmware" FORCE)
endif()

# The image of a bank (dmboot): one build for both banks, linked for the window that the selector maps the bank into
set(DMBOOT_BANK "A" CACHE STRING "Bank (A or B) that the image is linked for, started by the selector; empty: the whole flash, no selector")
set(DMBOOT_BANK_IMAGE_WINDOW 0x43000000)
set(DMBOOT_BANK_ONE_BUILD ON)

# The external flash (/ext): the last 1.9 MB of the flash of the module, a littlefs on the block node of dmflash (flash.dmd, services/ext.ini).
# format-ext creates the file system, upload-ext sends build/ext over the console (YMODEM).
set(DMBOOT_EXT_DEVICE "/dev/dmflashx/ext" CACHE STRING "Block device of the external flash; empty: the board has none (format-ext, upload-ext are not defined)")
set(DMBOOT_EXT_FS "dmlittlefs" CACHE STRING "File system of the external flash")
set(DMBOOT_EXT_MKFS "mklittlefs" CACHE STRING "Command that creates it on the device (format-ext)")
set(DMBOOT_EXT_MOUNT "/ext" CACHE STRING "Where the external flash is mounted")

# The buffer of dmlog: nothing reads the log on this board, and its internal RAM is short (the display and the SD card need DMA memory).
# Tried: 2048 boots, 1024 does not (QEMU: no shell prompt).
set(DMBOOT_LOGS_SIZE 2048 CACHE STRING "Bytes of the buffer of dmlog")

# Splash logo the display driver (dmlcdtft) shows on the 800x480 panel as soon as it is up (an asset of assets/splash/, see
# DMBOOT_SPLASH_LOGO). It is built into the firmware (/eviews/splash_logo.dmvir): the display driver is a module of the firmware.
set(DMBOOT_SPLASH_LOGO "dmodos_logo_200" CACHE STRING "Splash logo the display driver shows at start")

# The board is used upright (the connector at the bottom): the display service turns every view by 90 degrees clockwise (DMVIEW_ROTATION), so
# a portrait view (dmodOS, 272 x 480) stands upright on the 800 x 480 panel.
set(DMBOOT_DISPLAY_ROTATION "90" CACHE STRING "Angle in degrees clockwise the display service turns the views by")
