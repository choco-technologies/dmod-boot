# ======================================================================
#               DMOD Tools Configuration
# ======================================================================
set(DMOD_TOOLS_NAME	"arch/armv7/cortex-m4" CACHE STRING "Name of the tools configuration")

# ======================================================================
#               QEMU Configuration for Cortex-M4
# ======================================================================
# This configuration is used when DMBOOT_QEMU=ON
if(DMBOOT_QEMU)
    set(DMBOOT_QEMU_MACHINE "netduinoplus2" CACHE STRING "QEMU machine type for Cortex-M4 emulation")
    set(DMBOOT_QEMU_CPU "cortex-m4" CACHE STRING "QEMU CPU type for Cortex-M4 emulation")
endif()