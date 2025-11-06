# ======================================================================
#               Configuration
# ======================================================================
set(DMBOOT_MCU_NAME "stm32f746zg" CACHE STRING "Name of the target microcontroller")
set(DMBOOT_MCU_SERIES "stm32f7" CACHE STRING "Series of the target microcontroller")
set(DMBOOT_ARCH "armv7" CACHE STRING "Architecture of the target microcontroller")
set(DMBOOT_ARCH_FAMILY "cortex-m7" CACHE STRING "Microcontroller family")

# ======================================================================
#               OpenOCD Configuration
# ======================================================================
find_program(OPENOCD openocd REQUIRED)
set(OPENOCD_INTERFACE "interface/stlink.cfg" CACHE STRING "OpenOCD interface configuration file")
set(OPENOCD_TARGET "target/stm32f7x.cfg" CACHE STRING "OpenOCD target configuration file")

# ======================================================================
#               DMOD Configuration
# ======================================================================
# Name of the target cpu (if empty, the target is generic)
set(DMOD_CPU_NAME   ${DMBOOT_MCU_NAME} CACHE STRING "Name of the target cpu, if empty, the target is generic")

# ======================================================================
#               Include architecture configuration
# ======================================================================
include(configs/arch/${DMBOOT_ARCH}/cfg.cmake)
include(configs/arch/${DMBOOT_ARCH}/${DMBOOT_ARCH_FAMILY}/cfg.cmake)