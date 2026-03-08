# ======================================================================
#               ARMv7 common library
# ======================================================================
add_library(dmboot_arch STATIC
    dmod_critical.c
    dmod_mutex.c
)

target_link_libraries(dmboot_arch
    PRIVATE 
        dmod
)

# Wrap Dmod_Mutex_New so the pre-RTOS guard is applied to all callers
# (e.g. dmvfs) that are linked into the final firmware image.
target_link_options(dmboot_arch INTERFACE -Wl,--wrap=Dmod_Mutex_New)

add_subdirectory(${DMBOOT_ARCH_FAMILY})