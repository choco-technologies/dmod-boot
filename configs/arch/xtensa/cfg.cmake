# ======================================================================
#               Xtensa objcopy format configuration
# ======================================================================
set(DMBOOT_OBJCOPY_OUTPUT_FORMAT "elf32-xtensa-le" CACHE STRING "objcopy output target format for Xtensa")
set(DMBOOT_OBJCOPY_BINARY_ARCH   "xtensa"          CACHE STRING "objcopy binary architecture for Xtensa")

# ======================================================================
#               IRQ configuration
# ======================================================================
set(DMBOOT_IRQ_COUNT 0 CACHE STRING "Number of external IRQ lines supported by the target")
set(DMBOOT_IRQ_MAX_HANDLERS_PER_IRQ 4 CACHE STRING "Maximum number of handlers registered per IRQ line")
