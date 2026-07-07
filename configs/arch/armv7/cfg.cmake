# ======================================================================
#               ARMv7 objcopy format configuration
# ======================================================================
set(DMBOOT_OBJCOPY_OUTPUT_FORMAT "elf32-littlearm" CACHE STRING "objcopy output target format for ARMv7")
set(DMBOOT_OBJCOPY_BINARY_ARCH   "arm"             CACHE STRING "objcopy binary architecture for ARMv7")

# ======================================================================
#               IRQ configuration
# ======================================================================
set(DMBOOT_IRQ_COUNT 98 CACHE STRING "Number of external IRQ lines supported by the target")
set(DMBOOT_IRQ_MAX_HANDLERS_PER_IRQ 4 CACHE STRING "Maximum number of handlers registered per IRQ line")
