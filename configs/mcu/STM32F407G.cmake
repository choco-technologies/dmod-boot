# ======================================================================
#               Configuration
# ======================================================================
set(DMBOOT_MCU_NAME "stm32f407g" CACHE STRING "Name of the target microcontroller")
set(DMBOOT_MCU_SERIES "stm32f4" CACHE STRING "Series of the target microcontroller")
set(DMBOOT_ARCH "armv7" CACHE STRING "Architecture of the target microcontroller")
set(DMBOOT_ARCH_FAMILY "cortex-m4" CACHE STRING "Microcontroller family")

# ======================================================================
#               RTOS Clock Configuration
# ======================================================================
set(DMOSI_CPU_CLOCK_HZ 180000000 CACHE STRING "CPU clock frequency for dmosi-freertos configuration")

# ======================================================================
#               OpenOCD Configuration
# ======================================================================
# OpenOCD is only required when not using QEMU mode
if(NOT DMBOOT_EMULATION)
    find_program(OPENOCD openocd REQUIRED)
endif()
set(OPENOCD_INTERFACE "interface/stlink.cfg" CACHE STRING "OpenOCD interface configuration file")
set(OPENOCD_TARGET "target/stm32f4x.cfg" CACHE STRING "OpenOCD target configuration file")

# ======================================================================
#               DMOD Configuration
# ======================================================================
# Name of the target cpu (if empty, the target is generic)
set(DMOD_CPU_NAME   ${DMBOOT_MCU_NAME} CACHE STRING "Name of the target cpu, if empty, the target is generic")

# ======================================================================
#               Renode Configuration
# ======================================================================
if(DMBOOT_EMULATION)
    # Use STM32F4 Discovery board - includes full peripheral emulation
    set(DMBOOT_RENODE_PLATFORM "platforms/boards/stm32f4_discovery.repl" CACHE STRING "Renode platform for STM32F407G")
endif()

# ======================================================================
#               Include architecture configuration
# ======================================================================
include(configs/arch/${DMBOOT_ARCH}/cfg.cmake)
include(configs/arch/${DMBOOT_ARCH}/${DMBOOT_ARCH_FAMILY}/cfg.cmake)