# This script sets up ROM filesystems using dmffs and integrates them into the build
# It checks for the required tools, creates the dmffs images, and embeds them into the firmware:
#   - DMBOOT_CONFIG_DIR -> section .embedded.config_fs, mounted at /configs/
#   - DMBOOT_EVIEWS_DIR -> section .embedded.eviews_fs, mounted at /eviews/

# Find make_dmffs tool (sets MAKE_DMFFS_COMMAND)
function(dmboot_find_make_dmffs)
    if(MAKE_DMFFS_COMMAND)
        return()
    endif()

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
            set(MAKE_DMFFS_COMMAND "${DMOD_LOADER}" "make_dmffs.dmf" "--args" PARENT_SCOPE)
        else()
            message(FATAL_ERROR "Could not find make_dmffs tool. Please install it or set DMOD_DMF_DIR environment variable")
        endif()
    else()
        find_program(DMOD_LOADER dmod_loader)
        if(DMOD_LOADER)
            set(MAKE_DMFFS_COMMAND "${DMOD_LOADER}" "${MAKE_DMFFS_MODULE}" "--args" PARENT_SCOPE)
        else()
            message(FATAL_ERROR "Could not find dmod_loader executable")
        endif()
    endif()
endfunction()

#
# Create a dmffs image from a directory and embed it into a ROM section
#
# Usage:
#   dmboot_embed_dmffs(<name> <source_dir> <section> <out_object_var>)
#
# <name>     base name of the generated files (<build>/<name>.dmffs, <build>/__<name>.o)
#            and of the generate_<name> target
# <section>  linker section the image is placed in (see linker/common.ld)
#
function(dmboot_embed_dmffs name sourceDir section outObjectVar)
    file(MAKE_DIRECTORY "${sourceDir}")
    dmboot_find_make_dmffs()

    set(FS_IMAGE "${CMAKE_BINARY_DIR}/${name}.dmffs")
    set(FS_OBJECT "${CMAKE_BINARY_DIR}/__${name}.o")

    # The images depend on the download marker: dmf-get drops files into the
    # existing subdirectories, which leaves the directory's own mtime untouched,
    # so a directory-only dependency silently ships a stale image.
    add_custom_command(
        OUTPUT "${FS_IMAGE}"
        COMMAND ${MAKE_DMFFS_COMMAND} "${sourceDir}" "${FS_IMAGE}"
        DEPENDS "${sourceDir}" "${DMBOOT_MODULES_MARKER_FILE}" download_modules
        COMMENT "Creating ${name} filesystem image from ${sourceDir}"
        VERBATIM
    )

    add_custom_target(generate_${name}
        DEPENDS "${FS_IMAGE}"
    )

    add_custom_command(
        OUTPUT "${FS_OBJECT}"
        COMMAND ${CMAKE_OBJCOPY}
            --input-target=binary
            --output-target=${DMBOOT_OBJCOPY_OUTPUT_FORMAT}
            --binary-architecture=${DMBOOT_OBJCOPY_BINARY_ARCH}
            --rename-section .data=${section},alloc,load,readonly,data,contents
            "${FS_IMAGE}"
            "${FS_OBJECT}"
        DEPENDS "${FS_IMAGE}"
        COMMENT "Embedding ${name} filesystem into section ${section}"
        VERBATIM
    )

    set(${outObjectVar} "${FS_OBJECT}" PARENT_SCOPE)
    message(STATUS "${name} filesystem will be embedded from: ${sourceDir}")
endfunction()

# Config filesystem (/configs/)
if(DMBOOT_CONFIG_DIR)
    message(STATUS "Config directory specified: ${DMBOOT_CONFIG_DIR}")
    dmboot_embed_dmffs(config_fs "${DMBOOT_CONFIG_DIR}" .embedded.config_fs CONFIG_FS_OBJECT)
    set(CONFIG_FS_IMAGE "${CMAKE_BINARY_DIR}/config_fs.dmffs")
else()
    message(STATUS "No config directory specified (DMBOOT_CONFIG_DIR not set)")
endif()

# Embedded views filesystem (/eviews/) - views of the modules installed to flash,
# one subdirectory per module (created by dmf-get --views-dir)
if(DMBOOT_EVIEWS_DIR)
    message(STATUS "Embedded views directory specified: ${DMBOOT_EVIEWS_DIR}")
    dmboot_embed_dmffs(eviews_fs "${DMBOOT_EVIEWS_DIR}" .embedded.eviews_fs EVIEWS_FS_OBJECT)
    set(EVIEWS_FS_IMAGE "${CMAKE_BINARY_DIR}/eviews_fs.dmffs")
else()
    message(STATUS "No embedded views directory specified (DMBOOT_EVIEWS_DIR not set)")
endif()
