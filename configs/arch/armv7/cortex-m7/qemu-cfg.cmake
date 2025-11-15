# ======================================================================
#               QEMU Configuration for Cortex-M7
# ======================================================================
# This file contains QEMU emulation settings for Cortex-M7 targets
# Different MCUs using Cortex-M7 may override these if needed
#
# Note: mps2-an500 is the ARM MPS2 board with AN500 FPGA image for Cortex-M7
# This board was added in QEMU 2.6.0 (2016). If using older QEMU versions,
# you may need to use an alternative like 'lm3s6965evb' (Cortex-M3) as fallback.

set(DMBOOT_QEMU_MACHINE "mps2-an500" CACHE STRING "QEMU machine type for Cortex-M7 emulation")
set(DMBOOT_QEMU_CPU "cortex-m7" CACHE STRING "QEMU CPU type for Cortex-M7 emulation")
