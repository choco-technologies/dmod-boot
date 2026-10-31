# Board configuration for STM32F746G Discovery
# Sets TARGET for the build system
set(TARGET "STM32F746xG" CACHE STRING "Target microcontroller" FORCE)

# Splash logo dmlcdtft shows on the 480x272 LCD as soon as it is up (an asset
# of assets/splash/, see DMBOOT_SPLASH_LOGO)
set(DMBOOT_SPLASH_LOGO "dmodos_logo_128" CACHE STRING "Splash logo the display driver shows at start")
# UART the first console (tty0, dmuart "stlink_vcp" = USART1, the ST-Link
# virtual COM port) runs on, as named in the Renode platform - emulation mode
# exposes it as a TCP terminal (see DMBOOT_RENODE_UART_PORT)
set(DMBOOT_RENODE_CONSOLE_UART "sysbus.usart1" CACHE STRING "Renode peripheral of the console UART")

# Ethernet controller (eth0) as named in the Renode platform - emulation mode
# can connect it to a TAP interface on the host (see DMBOOT_RENODE_TAP)
set(DMBOOT_RENODE_ETHERNET "sysbus.ethernet" CACHE STRING "Renode peripheral of the Ethernet controller")

# microSD slot (SDMMC1, card detect PC13 low when a card is inserted) as named
# in the Renode platform - emulation mode can insert a card image in it (see
# DMBOOT_RENODE_SDCARD). Renode's SDMMC model does not behave like the
# hardware where dmsdio relies on it, so it is replaced with
# configs/renode/STM32F7_SDMMC.cs, wired like the platform's own.
set(DMBOOT_RENODE_SDMMC "sysbus.sdmmc" CACHE STRING "Renode peripheral of the SD card host")
set(DMBOOT_RENODE_SDMMC_MODEL "${CMAKE_SOURCE_DIR}/configs/renode/STM32F7_SDMMC.cs")
set(DMBOOT_RENODE_SDMMC_DESCRIPTION "sdmmc: SD.STM32F7_SDMMC @ sysbus 0x40012c00 { IRQ -> nvic@49; DMAReceive -> dma2@3 }")
set(DMBOOT_RENODE_SDCARD_DETECT_GPIO "sysbus.gpioPortC")
set(DMBOOT_RENODE_SDCARD_DETECT_PIN 13)

# LCD-TFT controller (LTDC, dmlcdtft) as named in the Renode platform -
# emulation mode can write the frames it renders to a file (see
# DMBOOT_RENODE_LCD_CAPTURE)
set(DMBOOT_RENODE_LCD "sysbus.ltdc" CACHE STRING "Renode peripheral of the LCD controller")

# Audio (WM8994 codec on I2C3 address 0x1A, fed by SAI2): Renode has neither
# peripheral, and its DMA2 has no circular mode or half-transfer interrupt,
# which the SAI stream needs - configs/renode/STM32F7_Audio.cs supplies all
# three. Emulation mode loads them when DMBOOT_RENODE_AUDIO_CAPTURE is set
# (see there); DMA2 is replaced by a model that moves peripheral-to-memory
# data like Renode's own, so the SD host still works. <capture> stands for the
# file the codec writes what it plays to.
set(DMBOOT_RENODE_AUDIO_MODEL "${CMAKE_SOURCE_DIR}/configs/renode/STM32F7_Audio.cs")
set(DMBOOT_RENODE_AUDIO_DMA "sysbus.dma2")
set(DMBOOT_RENODE_AUDIO_DMA_DESCRIPTION "dma2: DMA.STM32F7_AudioDMA @ sysbus 0x40026400 { [0-7] -> nvic@[56-60,68-70] }")
set(DMBOOT_RENODE_AUDIO_CODEC_DESCRIPTION "wm8994: Sound.WM8994 @ i2c3 0x1A { outputFile: \\\"<capture>\\\" }")
set(DMBOOT_RENODE_AUDIO_SAI_DESCRIPTION "sai2: Sound.STM32F7_SAI @ sysbus 0x40015C00 { codec: wm8994; DmaRequestA -> dma2@4; DmaRequestB -> dma2@6 }")

# The external flash (see docs/external-flash.md): the block node of the chip, the file system on it and where it is
# mounted (the "ext" service, services/ext.ini). format-ext / upload-ext use them.
set(DMBOOT_EXT_DEVICE "/dev/dmspiflashx/flash" CACHE STRING "Block device of the external flash; empty: the board has none (format-ext, upload-ext are not defined)")
set(DMBOOT_EXT_FS "dmlittlefs" CACHE STRING "File system of the external flash")
set(DMBOOT_EXT_MKFS "mklittlefs" CACHE STRING "Command that creates it on the device (format-ext)")
set(DMBOOT_EXT_MOUNT "/ext" CACHE STRING "Where the external flash is mounted")
# flash.dmd keeps what brings /ext up (the console, the clocks, the SDRAM, the chain to the chip, the file system, ls,
# mount, umount, ymodem, mklittlefs - format-ext and upload-ext need them); the shell tools of configs/common/tools.dmd
# and ext.dmd (the network, the SD card, the display, the audio, ...) are on /ext, in Renode too: upload-ext sends them.
# The default vault is /ext/secrets.vault (wifid waits for the file to appear).
set(DMBOOT_EXT_TOOLS ON CACHE BOOL "Put the shell tools and the services of tools.dmd on the external flash instead of in the firmware")
# (a cache entry that already exists is not changed - pass -DDMBOOT_DMSECRETS_PATH=...)
set(DMBOOT_DMSECRETS_PATH "/ext/secrets.vault" CACHE STRING "Path of the default dmsecrets vault (DMSECRETS_PATH at boot); empty: not set")
# The display driver is on /ext: the splash logo (60 kB of raw pixels) is too, and shows as soon as /ext is mounted.
set(DMBOOT_SPLASH_LOGO_PATH "/ext/views/splash_logo.dmvir" CACHE STRING "Path of the splash logo (.dmvir) on the target")

# Dual bank layout of the internal flash (selector/): S0 the selector, S1 its store (the state of the banks, the persistent
# items), S2 and S3 the file systems of the banks, A = S4+S5, B = S6+S7 (384 kB each; the header of the image takes the first
# 512 bytes of a bank, the vectors follow). The firmware is linked for the bank A by default (and installed with the
# selector); -DDMBOOT_BANK=B links it for the other one, -DDMBOOT_BANK= for the whole flash without the selector. The
# emulation (Renode) loads the plain image.
if(NOT DMBOOT_EMULATION)
    set(DMBOOT_BANK "A" CACHE STRING "Bank (A or B) that the image is linked for, started by the selector; empty: the whole flash, no selector")
endif()
set(DMBOOT_BANK_A_ORIGIN 0x08020000)
set(DMBOOT_BANK_A_SIZE   0x00060000)
set(DMBOOT_BANK_B_ORIGIN 0x08080000)
set(DMBOOT_BANK_B_SIZE   0x00060000)
set(DMBOOT_SELECTOR_ORIGIN 0x08000000)
set(DMBOOT_SELECTOR_STORE  0x08008000)
set(DMBOOT_SELECTOR_STORE_SECTOR 1)

# QUADSPI bank 1 + N25Q128A, DMA2 stream 7/channel 3, IRQ 92 (RM0385).
set(DMBOOT_RENODE_QSPI_MODEL "${CMAKE_SOURCE_DIR}/configs/renode/STM32F7_QUADSPI.cs")
