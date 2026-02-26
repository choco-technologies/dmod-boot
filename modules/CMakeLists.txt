# ======================================================================
#               Collecting flash.dmd files (common + MCU + board)
# ======================================================================
set(DMBOOT_FLASH_DMD_FILES "")

# Common flash modules
set(_COMMON_FLASH_DMD "${CMAKE_SOURCE_DIR}/configs/common/flash.dmd")
if(EXISTS "${_COMMON_FLASH_DMD}")
    list(APPEND DMBOOT_FLASH_DMD_FILES "${_COMMON_FLASH_DMD}")
endif()

# MCU-specific flash modules
set(_MCU_FLASH_DMD "${CMAKE_SOURCE_DIR}/configs/mcu/${DMBOOT_MCU_SERIES}/${DMBOOT_MCU_NAME}/flash.dmd")
if(EXISTS "${_MCU_FLASH_DMD}")
    list(APPEND DMBOOT_FLASH_DMD_FILES "${_MCU_FLASH_DMD}")
endif()

# Board-specific flash modules (only if BOARD is set)
if(BOARD)
    set(_BOARD_FLASH_DMD "${CMAKE_SOURCE_DIR}/configs/board/${BOARD}/flash.dmd")
    if(EXISTS "${_BOARD_FLASH_DMD}")
        list(APPEND DMBOOT_FLASH_DMD_FILES "${_BOARD_FLASH_DMD}")
    endif()
endif()

# Extra flash modules from cmake parameter
set(_EXTRA_FLASH_DMD_VALID_FILES "")
set(_EXTRA_FLASH_DMD_VALID_MANIFESTS "")
list(LENGTH DMBOOT_EXTRA_FLASH_DMD_FILES _EXTRA_FLASH_COUNT)
if(_EXTRA_FLASH_COUNT GREATER 0)
    math(EXPR _EXTRA_FLASH_LAST "${_EXTRA_FLASH_COUNT} - 1")
    foreach(_IDX RANGE 0 ${_EXTRA_FLASH_LAST})
        list(GET DMBOOT_EXTRA_FLASH_DMD_FILES ${_IDX} _EXTRA_FLASH_DMD)
        if(EXISTS "${_EXTRA_FLASH_DMD}")
            list(APPEND _EXTRA_FLASH_DMD_VALID_FILES "${_EXTRA_FLASH_DMD}")
            list(LENGTH DMBOOT_EXTRA_FLASH_DMD_MANIFESTS _FLASH_MANIFEST_COUNT)
            if(_IDX LESS _FLASH_MANIFEST_COUNT)
                list(GET DMBOOT_EXTRA_FLASH_DMD_MANIFESTS ${_IDX} _EXTRA_FLASH_MANIFEST)
            else()
                set(_EXTRA_FLASH_MANIFEST "")
            endif()
            list(APPEND _EXTRA_FLASH_DMD_VALID_MANIFESTS "${_EXTRA_FLASH_MANIFEST}")
        else()
            message(WARNING "Extra flash.dmd file not found: ${_EXTRA_FLASH_DMD}")
        endif()
    endforeach()
endif()

# ======================================================================
#               Collecting sdcard.dmd files (common + MCU + board)
# ======================================================================
set(DMBOOT_SDCARD_DMD_FILES "")

# Common sdcard modules
set(_COMMON_SDCARD_DMD "${CMAKE_SOURCE_DIR}/configs/common/sdcard.dmd")
if(EXISTS "${_COMMON_SDCARD_DMD}")
    list(APPEND DMBOOT_SDCARD_DMD_FILES "${_COMMON_SDCARD_DMD}")
endif()

# MCU-specific sdcard modules
set(_MCU_SDCARD_DMD "${CMAKE_SOURCE_DIR}/configs/mcu/${DMBOOT_MCU_SERIES}/${DMBOOT_MCU_NAME}/sdcard.dmd")
if(EXISTS "${_MCU_SDCARD_DMD}")
    list(APPEND DMBOOT_SDCARD_DMD_FILES "${_MCU_SDCARD_DMD}")
endif()

# Board-specific sdcard modules (only if BOARD is set)
if(BOARD)
    set(_BOARD_SDCARD_DMD "${CMAKE_SOURCE_DIR}/configs/board/${BOARD}/sdcard.dmd")
    if(EXISTS "${_BOARD_SDCARD_DMD}")
        list(APPEND DMBOOT_SDCARD_DMD_FILES "${_BOARD_SDCARD_DMD}")
    endif()
endif()

# Extra sdcard modules from cmake parameter
set(_EXTRA_SDCARD_DMD_VALID_FILES "")
set(_EXTRA_SDCARD_DMD_VALID_MANIFESTS "")
list(LENGTH DMBOOT_EXTRA_SDCARD_DMD_FILES _EXTRA_SDCARD_COUNT)
if(_EXTRA_SDCARD_COUNT GREATER 0)
    math(EXPR _EXTRA_SDCARD_LAST "${_EXTRA_SDCARD_COUNT} - 1")
    foreach(_IDX RANGE 0 ${_EXTRA_SDCARD_LAST})
        list(GET DMBOOT_EXTRA_SDCARD_DMD_FILES ${_IDX} _EXTRA_SDCARD_DMD)
        if(EXISTS "${_EXTRA_SDCARD_DMD}")
            list(APPEND _EXTRA_SDCARD_DMD_VALID_FILES "${_EXTRA_SDCARD_DMD}")
            list(LENGTH DMBOOT_EXTRA_SDCARD_DMD_MANIFESTS _SDCARD_MANIFEST_COUNT)
            if(_IDX LESS _SDCARD_MANIFEST_COUNT)
                list(GET DMBOOT_EXTRA_SDCARD_DMD_MANIFESTS ${_IDX} _EXTRA_SDCARD_MANIFEST)
            else()
                set(_EXTRA_SDCARD_MANIFEST "")
            endif()
            list(APPEND _EXTRA_SDCARD_DMD_VALID_MANIFESTS "${_EXTRA_SDCARD_MANIFEST}")
        else()
            message(WARNING "Extra sdcard.dmd file not found: ${_EXTRA_SDCARD_DMD}")
        endif()
    endforeach()
endif()

# ======================================================================
#               Handling local packages directory
# ======================================================================
if(DMBOOT_MAIN_MODULE_PACKAGES_DIR)
    if(NOT IS_DIRECTORY "${DMBOOT_MAIN_MODULE_PACKAGES_DIR}")
        message(WARNING "DMBOOT_MAIN_MODULE_PACKAGES_DIR is not a valid directory: ${DMBOOT_MAIN_MODULE_PACKAGES_DIR}")
    else()
        set(_LOCAL_MODULE_DIR "${DMBOOT_MAIN_MODULE_PACKAGES_DIR}/${DMBOOT_MAIN_MODULE}")
        set(_LOCAL_MODULE_DMD "${_LOCAL_MODULE_DIR}/${DMBOOT_MAIN_MODULE}.dmd")
        set(_LOCAL_MANIFEST "${DMBOOT_MAIN_MODULE_PACKAGES_DIR}/manifest-local.dmm")

        if(EXISTS "${_LOCAL_MODULE_DMD}")
            if(EXISTS "${_LOCAL_MANIFEST}")
                message(STATUS "Using local packages for main module '${DMBOOT_MAIN_MODULE}' with manifest: ${_LOCAL_MANIFEST}")
                list(APPEND _EXTRA_FLASH_DMD_VALID_FILES "${_LOCAL_MODULE_DMD}")
                list(APPEND _EXTRA_FLASH_DMD_VALID_MANIFESTS "${_LOCAL_MANIFEST}")
            else()
                message(STATUS "Local manifest not found at ${_LOCAL_MANIFEST}, using remote manifest for local module dependencies")
                list(APPEND _EXTRA_FLASH_DMD_VALID_FILES "${_LOCAL_MODULE_DMD}")
                list(APPEND _EXTRA_FLASH_DMD_VALID_MANIFESTS "")
            endif()
        else()
            message(WARNING "No .dmd file found at ${_LOCAL_MODULE_DMD}. Skipping local installation of module '${DMBOOT_MAIN_MODULE}'.")
        endif()
    endif()
endif()

# ======================================================================
#               Downloading modules from DMD 
# ======================================================================
find_program(DMF_GET dmf-get HINTS ${DMBOOT_TOOLS_DIR})
if(NOT DMF_GET)
    message(FATAL_ERROR "dmf-get tool not found. Please build and install dmod tools first.")
endif()

set(DMBOOT_MODULES_OUT_DIR "${CMAKE_BINARY_DIR}/dmf")
set(DMBOOT_MODULES_MARKER_FILE "${DMBOOT_MODULES_OUT_DIR}/.download_complete")

if(DMBOOT_FLASH_DMD_FILES OR _EXTRA_FLASH_DMD_VALID_FILES)
    # Build a sequence of download commands, one per flash.dmd file
    set(_FLASH_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_MODULES_OUT_DIR}"
    )
    foreach(_DMD_FILE IN LISTS DMBOOT_FLASH_DMD_FILES)
        list(APPEND _FLASH_DOWNLOAD_COMMANDS
            COMMAND ${CMAKE_COMMAND} -E echo "Downloading flash modules from ${_DMD_FILE}..."
            COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
        )
    endforeach()
    list(LENGTH _EXTRA_FLASH_DMD_VALID_FILES _EXTRA_FLASH_VALID_COUNT)
    if(_EXTRA_FLASH_VALID_COUNT GREATER 0)
        math(EXPR _EXTRA_FLASH_VALID_LAST "${_EXTRA_FLASH_VALID_COUNT} - 1")
        foreach(_IDX RANGE 0 ${_EXTRA_FLASH_VALID_LAST})
            list(GET _EXTRA_FLASH_DMD_VALID_FILES ${_IDX} _DMD_FILE)
            list(GET _EXTRA_FLASH_DMD_VALID_MANIFESTS ${_IDX} _MANIFEST)
            if(_MANIFEST)
                list(APPEND _FLASH_DOWNLOAD_COMMANDS
                    COMMAND ${CMAKE_COMMAND} -E echo "Downloading flash modules from ${_DMD_FILE} (manifest: ${_MANIFEST})..."
                    COMMAND ${DMF_GET} -d "${_DMD_FILE}" -m "${_MANIFEST}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
                )
            else()
                list(APPEND _FLASH_DOWNLOAD_COMMANDS
                    COMMAND ${CMAKE_COMMAND} -E echo "Downloading flash modules from ${_DMD_FILE}..."
                    COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
                )
            endif()
        endforeach()
    endif()
    list(APPEND _FLASH_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_MODULES_MARKER_FILE}"
    )

    add_custom_command(
        OUTPUT "${DMBOOT_MODULES_MARKER_FILE}"
        ${_FLASH_DOWNLOAD_COMMANDS}
        DEPENDS ${DMBOOT_FLASH_DMD_FILES} ${_EXTRA_FLASH_DMD_VALID_FILES}
        COMMENT "Downloading flash modules from: ${DMBOOT_FLASH_DMD_FILES} ${_EXTRA_FLASH_DMD_VALID_FILES}"
        VERBATIM
    )
    add_custom_target(download_modules ALL
        DEPENDS "${DMBOOT_MODULES_MARKER_FILE}"
    )
    message(STATUS "Flash DMD files: ${DMBOOT_FLASH_DMD_FILES} ${_EXTRA_FLASH_DMD_VALID_FILES}")
else()
    message(WARNING "No flash.dmd files found. Skipping flash module download.")
    add_custom_target(download_modules ALL)
endif()

# ======================================================================
#               Downloading sdcard modules
# ======================================================================
set(DMBOOT_SDCARD_OUT_DIR "${CMAKE_BINARY_DIR}/sdcard")
set(DMBOOT_SDCARD_MARKER_FILE "${DMBOOT_SDCARD_OUT_DIR}/.download_complete")

if(DMBOOT_SDCARD_DMD_FILES OR _EXTRA_SDCARD_DMD_VALID_FILES)
    set(_SDCARD_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_SDCARD_OUT_DIR}"
    )
    foreach(_DMD_FILE IN LISTS DMBOOT_SDCARD_DMD_FILES)
        list(APPEND _SDCARD_DOWNLOAD_COMMANDS
            COMMAND ${CMAKE_COMMAND} -E echo "Downloading sdcard modules from ${_DMD_FILE}..."
            COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_SDCARD_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
        )
    endforeach()
    list(LENGTH _EXTRA_SDCARD_DMD_VALID_FILES _EXTRA_SDCARD_VALID_COUNT)
    if(_EXTRA_SDCARD_VALID_COUNT GREATER 0)
        math(EXPR _EXTRA_SDCARD_VALID_LAST "${_EXTRA_SDCARD_VALID_COUNT} - 1")
        foreach(_IDX RANGE 0 ${_EXTRA_SDCARD_VALID_LAST})
            list(GET _EXTRA_SDCARD_DMD_VALID_FILES ${_IDX} _DMD_FILE)
            list(GET _EXTRA_SDCARD_DMD_VALID_MANIFESTS ${_IDX} _MANIFEST)
            if(_MANIFEST)
                list(APPEND _SDCARD_DOWNLOAD_COMMANDS
                    COMMAND ${CMAKE_COMMAND} -E echo "Downloading sdcard modules from ${_DMD_FILE} (manifest: ${_MANIFEST})..."
                    COMMAND ${DMF_GET} -d "${_DMD_FILE}" -m "${_MANIFEST}" -o "${DMBOOT_SDCARD_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
                )
            else()
                list(APPEND _SDCARD_DOWNLOAD_COMMANDS
                    COMMAND ${CMAKE_COMMAND} -E echo "Downloading sdcard modules from ${_DMD_FILE}..."
                    COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_SDCARD_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
                )
            endif()
        endforeach()
    endif()
    list(APPEND _SDCARD_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_SDCARD_MARKER_FILE}"
    )

    add_custom_command(
        OUTPUT "${DMBOOT_SDCARD_MARKER_FILE}"
        ${_SDCARD_DOWNLOAD_COMMANDS}
        DEPENDS ${DMBOOT_SDCARD_DMD_FILES} ${_EXTRA_SDCARD_DMD_VALID_FILES}
        COMMENT "Downloading sdcard modules from: ${DMBOOT_SDCARD_DMD_FILES} ${_EXTRA_SDCARD_DMD_VALID_FILES}"
        VERBATIM
    )
    add_custom_target(download_sdcard_modules ALL
        DEPENDS "${DMBOOT_SDCARD_MARKER_FILE}"
    )
    message(STATUS "Sdcard DMD files: ${DMBOOT_SDCARD_DMD_FILES} ${_EXTRA_SDCARD_DMD_VALID_FILES}")
else()
    message(STATUS "No sdcard.dmd files found. Skipping sdcard module download.")
    add_custom_target(download_sdcard_modules ALL)
endif()

# ======================================================================
#               Preparing dmp file from flash modules
# ======================================================================
find_program(TODMP todmp HINTS ${DMBOOT_TOOLS_DIR})
if(NOT TODMP)
    message(FATAL_ERROR "todmp tool not found. Please build and install dmod tools first.")
endif()
set(DMBOOT_MODULES_DMP "${CMAKE_BINARY_DIR}/modules.dmp")

add_custom_command(
    OUTPUT "${DMBOOT_MODULES_DMP}"
    WORKING_DIRECTORY ${DMBOOT_MODULES_OUT_DIR}
    COMMAND ${CMAKE_COMMAND} -E echo "Checking if modules directory contains files..."
    COMMAND ${CMAKE_COMMAND} -E echo "Contents of ${DMBOOT_MODULES_OUT_DIR}:"
    COMMAND ls -la ${DMBOOT_MODULES_OUT_DIR} || ${CMAKE_COMMAND} -E echo "Directory is empty or does not exist"
    COMMAND bash -c "if ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf 1> /dev/null 2>&1; then ${TODMP} modules ${DMBOOT_MODULES_OUT_DIR} ${DMBOOT_MODULES_DMP} ${DMBOOT_MAIN_MODULE}; ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf; else echo 'No .dmf files found'; fi"
    DEPENDS download_modules
    COMMENT "Creating modules dmp file from flash modules (if any exist)..."
    VERBATIM
)
add_custom_target(prepare_modules_dmp ALL
    DEPENDS "${DMBOOT_MODULES_DMP}"
)