# ======================================================================
#               Startup library – Xtensa LX7
# ======================================================================
add_library(dmboot_startup STATIC
    startup.S
)

# Assembler files need a C-compatible linker language hint
set_target_properties(dmboot_startup PROPERTIES LINKER_LANGUAGE C)


# ======================================================================
#               Caches (the external RAM of the ESP32-S3)
# ======================================================================
# An object library: its Dmod_SyncCode() replaces the weak default of dmod, which a static library's member would not be linked
# for (the same as the Cortex-M7 caches).
add_library(dmboot_cpu OBJECT
    caches.c
    flash.c
)

dmod_set_current_allocator(dmboot_cpu)

target_link_libraries(dmboot_cpu
    PRIVATE
        dmod
)
