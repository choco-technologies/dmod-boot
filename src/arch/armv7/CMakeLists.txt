# ======================================================================
#               ARMv7 common library
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

# Include the override unconditionally: a weak SAL default already satisfies
# the symbol, so a static archive member would otherwise not be extracted.
add_library(dmboot_power OBJECT dmod_reboot.c)
dmod_set_current_allocator(dmboot_power)
target_link_libraries(dmboot_power PRIVATE dmod)
