# ======================================================================
#               Startup library – Xtensa LX7
# ======================================================================
add_library(dmboot_startup STATIC
    startup.S
)

# Assembler files need a C-compatible linker language hint
set_target_properties(dmboot_startup PROPERTIES LINKER_LANGUAGE C)
