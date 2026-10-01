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
