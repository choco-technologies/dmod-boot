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

# ======================================================================
#               Downloading modules from DMD 
# ======================================================================
find_program(DMF_GET dmf-get HINTS ${DMBOOT_TOOLS_DIR})
if(NOT DMF_GET)
    message(FATAL_ERROR "dmf-get tool not found. Please build and install dmod tools first.")
endif()

set(DMBOOT_MODULES_OUT_DIR "${CMAKE_BINARY_DIR}/dmf")
set(DMBOOT_MODULES_MARKER_FILE "${DMBOOT_MODULES_OUT_DIR}/.download_complete")

if(DMBOOT_FLASH_DMD_FILES)
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
        list(APPEND _SDCARD_DOWNLOAD_COMMANDS
            COMMAND ${CMAKE_COMMAND} -E echo "Downloading sdcard modules from ${_DMD_FILE}..."
            COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_SDCARD_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf --config-dir "${DMBOOT_CONFIG_DIR}"
        )
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

add_custom_command(
    OUTPUT "${DMBOOT_MODULES_DMP}"
    WORKING_DIRECTORY ${DMBOOT_MODULES_OUT_DIR}
    COMMAND ${CMAKE_COMMAND} -E echo "Checking if modules directory contains files..."
    COMMAND ${CMAKE_COMMAND} -E echo "Contents of ${DMBOOT_MODULES_OUT_DIR}:"
    COMMAND ls -la ${DMBOOT_MODULES_OUT_DIR} || ${CMAKE_COMMAND} -E echo "Directory is empty or does not exist"
    COMMAND bash -c "if ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf 1> /dev/null 2>&1; then ${TODMP} modules ${DMBOOT_MODULES_OUT_DIR} ${DMBOOT_MODULES_DMP} dmell; ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf; else echo 'No .dmf files found'; fi"
    DEPENDS download_modules
    COMMENT "Creating modules dmp file from flash modules (if any exist)..."
    VERBATIM
)
add_custom_target(prepare_modules_dmp ALL
    DEPENDS "${DMBOOT_MODULES_DMP}"
)