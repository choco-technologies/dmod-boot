# ======================================================================
#               DMOD Tools Configuration
# ======================================================================
set(DMOD_TOOLS_NAME	"arch/armv7/cortex-m7" CACHE STRING "Name of the tools configuration")

# ======================================================================
#               Renode Configuration for Cortex-M7
# ======================================================================
# This configuration is used when DMBOOT_EMULATION=ON
# Renode provides excellent STM32 emulation with full peripheral support
if(DMBOOT_EMULATION)
    # Use STM32F746 platform - Renode path: @platforms/cpus/stm32f7.repl
    set(DMBOOT_RENODE_PLATFORM "platforms/cpus/stm32f7.repl" CACHE STRING "Renode platform for Cortex-M7 emulation")
    set(DMBOOT_RENODE_MACHINE_NAME "stm32f746" CACHE STRING "Renode machine name")
endif()