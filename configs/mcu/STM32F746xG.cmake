# ======================================================================
#               Configuration
# ======================================================================
set(DMBOOT_MCU_NAME "stm32f746xg" CACHE STRING "Name of the target microcontroller")
set(DMBOOT_MCU_SERIES "stm32f7" CACHE STRING "Series of the target microcontroller")
set(DMBOOT_ARCH "armv7" CACHE STRING "Architecture of the target microcontroller")
set(DMBOOT_ARCH_FAMILY "cortex-m7" CACHE STRING "Microcontroller family")

# ======================================================================
#               RTOS Clock Configuration
# ======================================================================
set(DMOSI_CPU_CLOCK_HZ 216000000 CACHE STRING "CPU clock frequency for dmosi-freertos configuration")

# ======================================================================
#               OpenOCD Configuration
# ======================================================================
# OpenOCD is only required when not using QEMU mode
if(NOT DMBOOT_EMULATION)
    find_program(OPENOCD openocd REQUIRED)
endif()
set(OPENOCD_INTERFACE "interface/stlink.cfg" CACHE STRING "OpenOCD interface configuration file")
set(OPENOCD_TARGET "target/stm32f7x.cfg" CACHE STRING "OpenOCD target configuration file")

# ======================================================================
#               DMOD Configuration
# ======================================================================
# Name of the target cpu (if empty, the target is generic)
set(DMOD_CPU_NAME   ${DMBOOT_MCU_NAME} CACHE STRING "Name of the target cpu, if empty, the target is generic")
set(DMBOOT_IRQ_COUNT 98 CACHE STRING "Number of external IRQ lines for this MCU")

# ======================================================================
#               Heaps
# ======================================================================
# The DMA heap is the DTCM: reached by DMA through the core's AHBS port, never
# in the data cache - and the fastest RAM there is (no wait states, beside the
# cache): also what modules get when they ask for "fast" memory (e.g. dmmp3's
# decoder state - 70 % of the CPU in the SDRAM, 15 % here)
set(DMBOOT_DMA_HEAP_TAGS "dma,fast,dtcm" CACHE STRING "Tags of the DMA heap (linker region dma)")

# ======================================================================
#               Renode Configuration
# ======================================================================
if(DMBOOT_EMULATION)
    # Use STM32F7 Discovery board - includes full peripheral emulation
    set(DMBOOT_RENODE_PLATFORM "platforms/boards/stm32f7_discovery-bb.repl" CACHE STRING "Renode platform for STM32F746xG")
endif()

# ======================================================================
#               Include architecture configuration
# ======================================================================
include(configs/arch/${DMBOOT_ARCH}/cfg.cmake)
include(configs/arch/${DMBOOT_ARCH}/${DMBOOT_ARCH_FAMILY}/cfg.cmake)


