# ======================================================================
#               DMOD Tools Configuration
# ======================================================================
set(DMOD_TOOLS_NAME	"arch/armv7/cortex-m7" CACHE STRING "Name of the tools configuration")

# ======================================================================
#               QEMU Configuration for Cortex-M7
# ======================================================================
# This configuration is used when DMBOOT_QEMU=ON
# Note: mps2-an500 is the ARM MPS2 board with AN500 FPGA image for Cortex-M7
# This board was added in QEMU 2.6.0 (2016). If using older QEMU versions,
# you may need to use an alternative like 'lm3s6965evb' (Cortex-M3) as fallback.
if(DMBOOT_QEMU)
    set(DMBOOT_QEMU_MACHINE "mps2-an500" CACHE STRING "QEMU machine type for Cortex-M7 emulation")
    set(DMBOOT_QEMU_CPU "cortex-m7" CACHE STRING "QEMU CPU type for Cortex-M7 emulation")
endif()