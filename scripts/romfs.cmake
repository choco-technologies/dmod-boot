# This script sets up a ROM filesystem using dmffs and integrates it into the build
# It checks for the required tools, creates the ROMFS image, and embeds it into the firmware

# Check if DMBOOT_CONFIG_DIR is set
if(DMBOOT_CONFIG_DIR)
    # Create the directory if it doesn't exist
    file(MAKE_DIRECTORY "${DMBOOT_CONFIG_DIR}")
    message(STATUS "Config directory specified: ${DMBOOT_CONFIG_DIR}")
    
    # Set output path for the config filesystem image
    set(CONFIG_FS_IMAGE "${CMAKE_BINARY_DIR}/config_fs.dmffs")
    
    # Find make_dmffs tool
    # First check if DMOD_DMF_DIR environment variable is set
    if(DEFINED ENV{DMOD_DMF_DIR})
        set(MAKE_DMFFS_MODULE "$ENV{DMOD_DMF_DIR}/make_dmffs.dmf")
        if(EXISTS "${MAKE_DMFFS_MODULE}")
            message(STATUS "Found make_dmffs.dmf at: ${MAKE_DMFFS_MODULE}")
        else()
            message(WARNING "DMOD_DMF_DIR is set but make_dmffs.dmf not found at: ${MAKE_DMFFS_MODULE}")
            set(MAKE_DMFFS_MODULE "")
        endif()
    endif()
    
    # If not found, try to use make_dmffs directly from PATH
    if(NOT MAKE_DMFFS_MODULE)
        find_program(DMOD_LOADER dmod_loader)
        if(DMOD_LOADER)
            message(STATUS "Found dmod_loader, will attempt to use make_dmffs module")
            set(MAKE_DMFFS_COMMAND "${DMOD_LOADER}" "make_dmffs.dmf" "--args")
        else()
            message(FATAL_ERROR "Could not find make_dmffs tool. Please install it or set DMOD_DMF_DIR environment variable")
        endif()
    else()
        find_program(DMOD_LOADER dmod_loader)
        if(DMOD_LOADER)
            set(MAKE_DMFFS_COMMAND "${DMOD_LOADER}" "${MAKE_DMFFS_MODULE}" "--args")
        else()
            message(FATAL_ERROR "Could not find dmod_loader executable")
        endif()
    endif()
    
    # Create custom command to generate the config filesystem image
    add_custom_command(
        OUTPUT "${CONFIG_FS_IMAGE}"
        COMMAND ${MAKE_DMFFS_COMMAND} "${DMBOOT_CONFIG_DIR}" "${CONFIG_FS_IMAGE}"
        DEPENDS "${DMBOOT_CONFIG_DIR}" download_modules
        COMMENT "Creating config filesystem image from ${DMBOOT_CONFIG_DIR}"
        VERBATIM
    )
    
    # Create a custom target to ensure the filesystem image is generated
    add_custom_target(generate_config_fs
        DEPENDS "${CONFIG_FS_IMAGE}"
    )
    
    # Create custom command to embed the config filesystem image (similar to modules.dmp approach)
    set(CONFIG_FS_OBJECT "${CMAKE_BINARY_DIR}/__config_fs.o")
    add_custom_command(
        OUTPUT "${CONFIG_FS_OBJECT}"
        COMMAND ${CMAKE_OBJCOPY}
            --input-target=binary
            --output-target=${DMBOOT_OBJCOPY_OUTPUT_FORMAT}
            --binary-architecture=${DMBOOT_OBJCOPY_BINARY_ARCH}
            --rename-section .data=.embedded.config_fs,alloc,load,readonly,data,contents
            "${CONFIG_FS_IMAGE}"
            "${CONFIG_FS_OBJECT}"
        DEPENDS "${CONFIG_FS_IMAGE}"
        COMMENT "Embedding config filesystem into section .embedded.config_fs"
        VERBATIM
    )
    
    # Export variables to parent scope
    set(CONFIG_FS_OBJECT "${CONFIG_FS_OBJECT}" PARENT_SCOPE)
    set(CONFIG_FS_IMAGE "${CONFIG_FS_IMAGE}" PARENT_SCOPE)
    
    message(STATUS "Config filesystem will be embedded from: ${DMBOOT_CONFIG_DIR}")
else()
    message(STATUS "No config directory specified (DMBOOT_CONFIG_DIR not set)")
endif() 