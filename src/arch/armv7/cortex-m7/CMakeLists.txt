# ======================================================================
#               Startup library
# ======================================================================
add_library(dmboot_startup STATIC
    startup.s
)

# Set language for assembly files
set_target_properties(dmboot_startup PROPERTIES LINKER_LANGUAGE C)
# ======================================================================
#               Caches (Cortex-M7)
# ======================================================================
# An object library: its low_level_init_1() and Dmod_SyncCode() replace
# weak defaults (startup.s, dmod), which a static library's member would not
# be linked for.
add_library(dmboot_cpu OBJECT
    caches.c
)

dmod_set_current_allocator(dmboot_cpu)

target_link_libraries(dmboot_cpu
    PRIVATE
        dmod
)
