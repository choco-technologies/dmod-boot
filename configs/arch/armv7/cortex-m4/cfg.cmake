# ======================================================================
#               DMOD Tools Configuration
# ======================================================================
set(DMOD_TOOLS_NAME	"arch/armv7/cortex-m4" CACHE STRING "Name of the tools configuration")

# ======================================================================
#               Renode Configuration for Cortex-M4
# ======================================================================
# This configuration is used when DMBOOT_EMULATION=ON
# Renode provides excellent STM32 emulation with full peripheral support
# Note: DMBOOT_RENODE_PLATFORM is defined in MCU-specific config files