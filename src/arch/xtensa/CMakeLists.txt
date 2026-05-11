# ======================================================================
#               Xtensa common library
# ======================================================================
add_library(dmboot_arch STATIC
    dmod_critical.c
)

target_link_libraries(dmboot_arch
    PRIVATE
        dmod
)

add_subdirectory(${DMBOOT_ARCH_FAMILY})
