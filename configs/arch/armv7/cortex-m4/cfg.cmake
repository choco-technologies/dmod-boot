# ======================================================================
#               DMOD Tools Configuration
# ======================================================================
set(DMOD_TOOLS_NAME	"arch/armv7/cortex-m4" CACHE STRING "Name of the tools configuration")

# ======================================================================
#               Renode Configuration for Cortex-M4
# ======================================================================
# This configuration is used when DMBOOT_QEMU=ON (kept as QEMU for backward compatibility)
# Renode provides better STM32 emulation than QEMU with full peripheral support
if(DMBOOT_QEMU)
    set(DMBOOT_RENODE_PLATFORM "stm32f4_discovery-kit" CACHE STRING "Renode platform for Cortex-M4 emulation")
endif()