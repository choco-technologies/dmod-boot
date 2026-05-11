# ======================================================================
#               Configuration
# ======================================================================
set(DMBOOT_MCU_NAME   "esp32s3fn16r8" CACHE STRING "Name of the target microcontroller")
set(DMBOOT_MCU_SERIES "esp32s3"       CACHE STRING "Series of the target microcontroller")
set(DMBOOT_ARCH       "xtensa"        CACHE STRING "Architecture of the target microcontroller")
set(DMBOOT_ARCH_FAMILY "lx7"          CACHE STRING "Microcontroller family")

# ======================================================================
#               RTOS Clock Configuration
# ======================================================================
set(DMOSI_CPU_CLOCK_HZ 240000000 CACHE STRING "CPU clock frequency for dmosi-freertos configuration")

# ======================================================================
#               OpenOCD Configuration
# ======================================================================
# OpenOCD is only required when not using emulation mode
if(NOT DMBOOT_EMULATION)
    find_program(OPENOCD openocd REQUIRED)
endif()
# ESP32-S3 has a built-in USB JTAG interface (no external probe required)
set(OPENOCD_INTERFACE "interface/esp_usb_jtag.cfg" CACHE STRING "OpenOCD interface configuration file")
set(OPENOCD_TARGET    "target/esp32s3.cfg"         CACHE STRING "OpenOCD target configuration file")

# ======================================================================
#               DMOD Configuration
# ======================================================================
set(DMOD_CPU_NAME ${DMBOOT_MCU_NAME} CACHE STRING "Name of the target cpu, if empty, the target is generic")

# ======================================================================
#               Include architecture configuration
# ======================================================================
include(configs/arch/${DMBOOT_ARCH}/cfg.cmake)
include(configs/arch/${DMBOOT_ARCH}/${DMBOOT_ARCH_FAMILY}/cfg.cmake)
