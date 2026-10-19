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

# The default dmsecrets vault (DMSECRETS_PATH at boot) lives on the external flash (the "ext" service mounts it
# at /ext, see services/ext.ini): a file there is private to the board and there before the card is. wifid waits
# for the file to appear. (A cache entry that already exists is not changed - pass -DDMBOOT_DMSECRETS_PATH=...)
set(DMBOOT_DMSECRETS_PATH "/ext/secrets.vault" CACHE STRING "Path of the default dmsecrets vault (DMSECRETS_PATH at boot); empty: not set")

# The external flash (see docs/external-flash.md): the block node of the chip, the file system on it and where it is
# mounted (the "ext" service, services/ext.ini). format-ext / upload-ext use them.
set(DMBOOT_EXT_DEVICE "/dev/dmspiflashx/flash" CACHE STRING "Block device of the external flash; empty: the board has none (format-ext, upload-ext are not defined)")
set(DMBOOT_EXT_FS "dmlittlefs" CACHE STRING "File system of the external flash")
set(DMBOOT_EXT_MKFS "mklittlefs" CACHE STRING "Command that creates it on the device (format-ext)")
set(DMBOOT_EXT_MOUNT "/ext" CACHE STRING "Where the external flash is mounted")
# The shell tools of configs/common/tools.dmd are not in the firmware but on /ext (upload-ext sends them): the ROM is small,
# and /ext is there before anyone types a command. ls, mount, umount, ymodem and mklittlefs stay (flash.dmd): they are
# what format-ext and upload-ext need.
set(DMBOOT_EXT_TOOLS ON CACHE BOOL "Put the shell tools of tools.dmd on the external flash instead of in the firmware")
