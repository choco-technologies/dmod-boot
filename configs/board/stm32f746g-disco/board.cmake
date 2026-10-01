# Board configuration for STM32F746G Discovery
# Sets TARGET for the build system
set(TARGET "STM32F746xG" CACHE STRING "Target microcontroller" FORCE)

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
