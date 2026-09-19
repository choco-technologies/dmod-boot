# ======================================================================
#               Xtensa common library
# ======================================================================
add_library(dmboot_arch STATIC
    dmod_critical.c
)

dmod_set_current_allocator(dmboot_arch)

target_link_libraries(dmboot_arch
    PRIVATE
        dmod
)

add_subdirectory(${DMBOOT_ARCH_FAMILY})
