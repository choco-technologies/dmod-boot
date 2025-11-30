add_subdirectory(dmod)
add_subdirectory(dmlist)

# Add DMOD_EXTERNAL_REGISTRATION definition to dmlist when enabled
# This allows dmlist to properly handle registration in the dmboot context
if(DMOD_EXTERNAL_REGISTRATION)
    target_compile_definitions(dmlist PRIVATE DMOD_EXTERNAL_REGISTRATION)
endif()

add_subdirectory(dmlog)
add_subdirectory(dmheap)
add_subdirectory(dmvfs)
add_subdirectory(dmenv)