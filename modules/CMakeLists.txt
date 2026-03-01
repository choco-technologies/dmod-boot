# ======================================================================
#               Collecting flash.dmd files (common + MCU + board)
# ======================================================================
set(DMBOOT_FLASH_DMD_FILES "")

# Common flash modules
set(_COMMON_FLASH_DMD "${CMAKE_SOURCE_DIR}/configs/common/flash.dmd")
if(EXISTS "${_COMMON_FLASH_DMD}")
    list(APPEND DMBOOT_FLASH_DMD_FILES "${_COMMON_FLASH_DMD}")
endif()

# MCU-specific flash modules (skip in emulation mode - hardware peripherals not needed for emulation testing)
if(NOT DMBOOT_EMULATION)
    set(_MCU_FLASH_DMD "${CMAKE_SOURCE_DIR}/configs/mcu/${DMBOOT_MCU_SERIES}/${DMBOOT_MCU_NAME}/flash.dmd")
    if(EXISTS "${_MCU_FLASH_DMD}")
        list(APPEND DMBOOT_FLASH_DMD_FILES "${_MCU_FLASH_DMD}")
    endif()
else()
    message(STATUS "Emulation mode: skipping MCU-specific flash modules")
endif()

# Board-specific flash modules (only if BOARD is set)
if(BOARD)
    set(_BOARD_FLASH_DMD "${CMAKE_SOURCE_DIR}/configs/board/${BOARD}/flash.dmd")
    if(EXISTS "${_BOARD_FLASH_DMD}")
        list(APPEND DMBOOT_FLASH_DMD_FILES "${_BOARD_FLASH_DMD}")
    endif()
endif()

# Extra flash modules from cmake parameter
foreach(_EXTRA_FLASH_DMD IN LISTS DMBOOT_EXTRA_FLASH_DMD_FILES)
    if(EXISTS "${_EXTRA_FLASH_DMD}")
        list(APPEND DMBOOT_FLASH_DMD_FILES "${_EXTRA_FLASH_DMD}")
    else()
        message(WARNING "Extra flash.dmd file not found: ${_EXTRA_FLASH_DMD}")
    endif()
endforeach()

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
foreach(_EXTRA_SDCARD_DMD IN LISTS DMBOOT_EXTRA_SDCARD_DMD_FILES)
    if(EXISTS "${_EXTRA_SDCARD_DMD}")
        list(APPEND DMBOOT_SDCARD_DMD_FILES "${_EXTRA_SDCARD_DMD}")
    else()
        message(WARNING "Extra sdcard.dmd file not found: ${_EXTRA_SDCARD_DMD}")
    endif()
endforeach()

# ======================================================================
#               Downloading modules from DMD 
# ======================================================================
find_program(DMF_GET dmf-get HINTS ${DMBOOT_TOOLS_DIR})
if(NOT DMF_GET)
    message(FATAL_ERROR "dmf-get tool not found. Please build and install dmod tools first.")
endif()

set(DMBOOT_MODULES_OUT_DIR "${CMAKE_BINARY_DIR}/dmf")
set(DMBOOT_MODULES_MARKER_FILE "${DMBOOT_MODULES_OUT_DIR}/.download_complete")

# Helper macro to append main module download commands to a list
macro(append_main_module_download_commands LIST_VAR)
    set(_MAIN_MODULE_ARGS ${DMBOOT_MAIN_MODULE})
    if(DMBOOT_MAIN_MODULE_CONFIG)
        list(APPEND _MAIN_MODULE_ARGS ${DMBOOT_MAIN_MODULE_CONFIG})
    endif()
    if(DMBOOT_MANIFEST_URL)
        list(APPEND ${LIST_VAR}
            COMMAND ${CMAKE_COMMAND} -E echo "Downloading main module ${DMBOOT_MAIN_MODULE} (manifest: ${DMBOOT_MANIFEST_URL})..."
            COMMAND ${DMF_GET} ${_MAIN_MODULE_ARGS} -m "${DMBOOT_MANIFEST_URL}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
            COMMAND bash -c "test -f '${DMBOOT_MODULES_OUT_DIR}/${DMBOOT_MAIN_MODULE}.dmf' || { echo 'ERROR: Main module ${DMBOOT_MAIN_MODULE}.dmf was not downloaded to ${DMBOOT_MODULES_OUT_DIR}. The manifest may not contain the module entry or dmf-get encountered an error.'; exit 1; }"
        )
    else()
        list(APPEND ${LIST_VAR}
            COMMAND ${CMAKE_COMMAND} -E echo "Downloading main module ${DMBOOT_MAIN_MODULE}..."
            COMMAND ${DMF_GET} ${_MAIN_MODULE_ARGS} -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
            COMMAND bash -c "test -f '${DMBOOT_MODULES_OUT_DIR}/${DMBOOT_MAIN_MODULE}.dmf' || { echo 'ERROR: Main module ${DMBOOT_MAIN_MODULE}.dmf was not downloaded to ${DMBOOT_MODULES_OUT_DIR}. Check if dmf-get encountered an error.'; exit 1; }"
        )
    endif()
endmacro()

if(DMBOOT_FLASH_DMD_FILES)
    # Build a sequence of download commands, one per flash.dmd file
    set(_FLASH_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_MODULES_OUT_DIR}"
    )
    foreach(_DMD_FILE IN LISTS DMBOOT_FLASH_DMD_FILES)
        set(_EFFECTIVE_MANIFEST "${DMBOOT_MANIFEST_URL}")
        if(_EFFECTIVE_MANIFEST)
            list(APPEND _FLASH_DOWNLOAD_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E echo "Downloading flash modules from ${_DMD_FILE} (manifest: ${_EFFECTIVE_MANIFEST})..."
                COMMAND ${DMF_GET} -d "${_DMD_FILE}" -m "${_EFFECTIVE_MANIFEST}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
            )
        else()
            list(APPEND _FLASH_DOWNLOAD_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E echo "Downloading flash modules from ${_DMD_FILE}..."
                COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
            )
        endif()
    endforeach()

    # Download main module if specified (at the end of installation),
    # but only if it is not already listed in any flash.dmd file
    if(DMBOOT_MAIN_MODULE)
        set(_MAIN_MODULE_IN_FLASH_DMD FALSE)
        foreach(_DMD_FILE IN LISTS DMBOOT_FLASH_DMD_FILES)
            file(STRINGS "${_DMD_FILE}" _DMD_LINES)
            foreach(_LINE IN LISTS _DMD_LINES)
                string(STRIP "${_LINE}" _LINE_STRIPPED)
                if(NOT _LINE_STRIPPED MATCHES "^#" AND NOT _LINE_STRIPPED STREQUAL "")
                    string(REGEX MATCH "^[^ \t\r\n]+" _LINE_MODULE_NAME "${_LINE_STRIPPED}")
                    if(_LINE_MODULE_NAME STREQUAL "${DMBOOT_MAIN_MODULE}")
                        set(_MAIN_MODULE_IN_FLASH_DMD TRUE)
                        break()
                    endif()
                endif()
            endforeach()
            if(_MAIN_MODULE_IN_FLASH_DMD)
                break()
            endif()
        endforeach()
        if(NOT _MAIN_MODULE_IN_FLASH_DMD)
            append_main_module_download_commands(_FLASH_DOWNLOAD_COMMANDS)
        else()
            message(STATUS "Main module '${DMBOOT_MAIN_MODULE}' is already listed in flash.dmd, skipping explicit download")
        endif()
    endif()

    list(APPEND _FLASH_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_MODULES_MARKER_FILE}"
    )

    add_custom_command(
        OUTPUT "${DMBOOT_MODULES_MARKER_FILE}"
        ${_FLASH_DOWNLOAD_COMMANDS}
        DEPENDS ${DMBOOT_FLASH_DMD_FILES}
        COMMENT "Downloading flash modules from: ${DMBOOT_FLASH_DMD_FILES}"
        VERBATIM
    )
    add_custom_target(download_modules ALL
        DEPENDS "${DMBOOT_MODULES_MARKER_FILE}"
    )
    message(STATUS "Flash DMD files: ${DMBOOT_FLASH_DMD_FILES}")
elseif(DMBOOT_MAIN_MODULE)
    # No flash.dmd files configured. Downloading main module only.
    message(STATUS "No flash.dmd files configured. Downloading main module only: ${DMBOOT_MAIN_MODULE}")
    set(_MAIN_MODULE_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_MODULES_OUT_DIR}"
    )
    append_main_module_download_commands(_MAIN_MODULE_COMMANDS)
    list(APPEND _MAIN_MODULE_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_MODULES_MARKER_FILE}"
    )
    add_custom_command(
        OUTPUT "${DMBOOT_MODULES_MARKER_FILE}"
        ${_MAIN_MODULE_COMMANDS}
        COMMENT "Downloading main module: ${DMBOOT_MAIN_MODULE}"
        VERBATIM
    )
    add_custom_target(download_modules ALL
        DEPENDS "${DMBOOT_MODULES_MARKER_FILE}"
    )
else()
    message(WARNING "No flash.dmd files found. Skipping flash module download.")
    add_custom_target(download_modules ALL)
endif()

# ======================================================================
#               Downloading sdcard modules
# ======================================================================
set(DMBOOT_SDCARD_OUT_DIR "${CMAKE_BINARY_DIR}/sdcard")
set(DMBOOT_SDCARD_MARKER_FILE "${DMBOOT_SDCARD_OUT_DIR}/.download_complete")

if(DMBOOT_SDCARD_DMD_FILES)
    set(_SDCARD_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_SDCARD_OUT_DIR}"
    )
    foreach(_DMD_FILE IN LISTS DMBOOT_SDCARD_DMD_FILES)
        set(_EFFECTIVE_MANIFEST "${DMBOOT_MANIFEST_URL}")
        if(_EFFECTIVE_MANIFEST)
            list(APPEND _SDCARD_DOWNLOAD_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E echo "Downloading sdcard modules from ${_DMD_FILE} (manifest: ${_EFFECTIVE_MANIFEST})..."
                COMMAND ${DMF_GET} -d "${_DMD_FILE}" -m "${_EFFECTIVE_MANIFEST}" -o "${DMBOOT_SDCARD_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
            )
        else()
            list(APPEND _SDCARD_DOWNLOAD_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E echo "Downloading sdcard modules from ${_DMD_FILE}..."
                COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_SDCARD_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
            )
        endif()
    endforeach()
    list(APPEND _SDCARD_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_SDCARD_MARKER_FILE}"
    )

    add_custom_command(
        OUTPUT "${DMBOOT_SDCARD_MARKER_FILE}"
        ${_SDCARD_DOWNLOAD_COMMANDS}
        DEPENDS ${DMBOOT_SDCARD_DMD_FILES}
        COMMENT "Downloading sdcard modules from: ${DMBOOT_SDCARD_DMD_FILES}"
        VERBATIM
    )
    add_custom_target(download_sdcard_modules ALL
        DEPENDS "${DMBOOT_SDCARD_MARKER_FILE}"
    )
    message(STATUS "Sdcard DMD files: ${DMBOOT_SDCARD_DMD_FILES}")
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

# When a main module is expected, fail the build if no .dmf files are found
# after the download step. Otherwise, just print a notice and succeed.
if(DMBOOT_MAIN_MODULE)
    add_custom_command(
        OUTPUT "${DMBOOT_MODULES_DMP}"
        WORKING_DIRECTORY ${DMBOOT_MODULES_OUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E echo "Checking if modules directory contains files..."
        COMMAND ${CMAKE_COMMAND} -E echo "Contents of ${DMBOOT_MODULES_OUT_DIR}:"
        COMMAND ls -la ${DMBOOT_MODULES_OUT_DIR} || ${CMAKE_COMMAND} -E echo "Directory is empty or does not exist"
        COMMAND bash -c "if ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf 1> /dev/null 2>&1; then ${TODMP} modules ${DMBOOT_MODULES_OUT_DIR} ${DMBOOT_MODULES_DMP} ${DMBOOT_MAIN_MODULE}; ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf; else echo 'ERROR: No .dmf files found in ${DMBOOT_MODULES_OUT_DIR} but main module ${DMBOOT_MAIN_MODULE} was expected. Module download may have failed.'; exit 1; fi"
        DEPENDS download_modules
        COMMENT "Creating modules dmp file from flash modules (if any exist)..."
        VERBATIM
    )
else()
    add_custom_command(
        OUTPUT "${DMBOOT_MODULES_DMP}"
        WORKING_DIRECTORY ${DMBOOT_MODULES_OUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E echo "Checking if modules directory contains files..."
        COMMAND ${CMAKE_COMMAND} -E echo "Contents of ${DMBOOT_MODULES_OUT_DIR}:"
        COMMAND ls -la ${DMBOOT_MODULES_OUT_DIR} || ${CMAKE_COMMAND} -E echo "Directory is empty or does not exist"
        COMMAND bash -c "if ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf 1> /dev/null 2>&1; then ${TODMP} modules ${DMBOOT_MODULES_OUT_DIR} ${DMBOOT_MODULES_DMP}; ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf; else echo 'No .dmf files found, skipping DMP creation'; fi"
        DEPENDS download_modules
        COMMENT "Creating modules dmp file from flash modules (if any exist)..."
        VERBATIM
    )
endif()
add_custom_target(prepare_modules_dmp ALL
    DEPENDS "${DMBOOT_MODULES_DMP}"
)
