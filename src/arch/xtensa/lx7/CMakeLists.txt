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


# ======================================================================
#               Fault handlers (the part of the Fault API of dmosi that is the architecture's)
# ======================================================================
# They take over the exception table of the port of FreeRTOS and rewrite the frame of the thread that faulted, so they use
# the structures of the port. Its targets (freertos_kernel, dmboot_idf_headers, see configs/arch/xtensa/lx7/freertos.cmake)
# are defined after this directory is processed; they are resolved when the build is generated. An object library, like the
# fault handlers of the Cortex-M: dmboot_xtensa_fault_init() and xt_debugexception() have to be linked in.
add_library(dmboot_fault OBJECT
    fault.c
    fault_asm.S
)

dmod_set_current_allocator(dmboot_fault)

target_link_libraries(dmboot_fault
    PRIVATE
        dmod
        dmosi
        freertos_kernel
        freertos_config
        dmboot_idf_headers
)
