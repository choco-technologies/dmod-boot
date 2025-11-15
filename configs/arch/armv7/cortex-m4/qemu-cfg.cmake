# ======================================================================
#               QEMU Configuration for Cortex-M4
# ======================================================================
# This file contains QEMU emulation settings for Cortex-M4 targets
# Different MCUs using Cortex-M4 may override these if needed

set(DMBOOT_QEMU_MACHINE "netduinoplus2" CACHE STRING "QEMU machine type for Cortex-M4 emulation")
set(DMBOOT_QEMU_CPU "cortex-m4" CACHE STRING "QEMU CPU type for Cortex-M4 emulation")
