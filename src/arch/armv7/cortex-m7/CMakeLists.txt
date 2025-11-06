# ======================================================================
#               Startup library
# ======================================================================
add_library(dmboot_startup STATIC
    startup.s
)

# Set language for assembly files
set_target_properties(dmboot_startup PROPERTIES LINKER_LANGUAGE C)