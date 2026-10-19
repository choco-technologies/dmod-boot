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

# The shell tools that are not needed to bring /ext up (configs/common/tools.dmd): in the firmware, or - on a board
# with an external flash (DMBOOT_EXT_TOOLS) - on /ext, in the ext modules below
set(_COMMON_TOOLS_DMD "${CMAKE_SOURCE_DIR}/configs/common/tools.dmd")
if(EXISTS "${_COMMON_TOOLS_DMD}" AND NOT DMBOOT_EXT_TOOLS)
    list(APPEND DMBOOT_FLASH_DMD_FILES "${_COMMON_TOOLS_DMD}")
endif()

# Board modules of the external flash (configs/board/<BOARD>/ext/flash.dmd): when the board has one (DMBOOT_EXT_DEVICE)
if(BOARD AND DMBOOT_EXT_DEVICE)
    set(_BOARD_EXT_FLASH_DMD "${CMAKE_SOURCE_DIR}/configs/board/${BOARD}/ext/flash.dmd")
    if(EXISTS "${_BOARD_EXT_FLASH_DMD}")
        list(APPEND DMBOOT_FLASH_DMD_FILES "${_BOARD_EXT_FLASH_DMD}")
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
#               Collecting ext.dmd files (common + MCU + board)
# ======================================================================
# The modules of ext.dmd are not in the firmware: they go to the external flash (/ext/bin, see
# docs/external-flash.md), like the ones of sdcard.dmd go to a card. upload-ext sends them.
set(DMBOOT_EXT_DMD_FILES "")
if(DMBOOT_EXT_DEVICE)

# Common ext modules
set(_COMMON_EXT_DMD "${CMAKE_SOURCE_DIR}/configs/common/ext.dmd")
if(EXISTS "${_COMMON_EXT_DMD}")
    list(APPEND DMBOOT_EXT_DMD_FILES "${_COMMON_EXT_DMD}")
endif()

# MCU-specific ext modules
set(_MCU_EXT_DMD "${CMAKE_SOURCE_DIR}/configs/mcu/${DMBOOT_MCU_SERIES}/${DMBOOT_MCU_NAME}/ext.dmd")
if(EXISTS "${_MCU_EXT_DMD}")
    list(APPEND DMBOOT_EXT_DMD_FILES "${_MCU_EXT_DMD}")
endif()

# The common tools, when they are on /ext
if(EXISTS "${_COMMON_TOOLS_DMD}" AND DMBOOT_EXT_TOOLS)
    list(APPEND DMBOOT_EXT_DMD_FILES "${_COMMON_TOOLS_DMD}")
endif()

# Board-specific ext modules (only if BOARD is set)
if(BOARD)
    set(_BOARD_EXT_DMD "${CMAKE_SOURCE_DIR}/configs/board/${BOARD}/ext.dmd")
    if(EXISTS "${_BOARD_EXT_DMD}")
        list(APPEND DMBOOT_EXT_DMD_FILES "${_BOARD_EXT_DMD}")
    endif()
endif()

# Extra ext modules from cmake parameter
foreach(_EXTRA_EXT_DMD IN LISTS DMBOOT_EXTRA_EXT_DMD_FILES)
    if(EXISTS "${_EXTRA_EXT_DMD}")
        list(APPEND DMBOOT_EXT_DMD_FILES "${_EXTRA_EXT_DMD}")
    else()
        message(WARNING "Extra ext.dmd file not found: ${_EXTRA_EXT_DMD}")
    endif()
endforeach()
endif()

# ======================================================================
#               Downloading modules from DMD
# ======================================================================
find_program(DMF_GET dmf-get HINTS ${DMBOOT_TOOLS_DIR})
if(NOT DMF_GET)
    message(FATAL_ERROR "dmf-get tool not found. Please build and install dmod tools first.")
endif()

execute_process(COMMAND "${DMF_GET}" --help
    RESULT_VARIABLE _DMF_GET_RESULT OUTPUT_VARIABLE _DMF_GET_HELP ERROR_VARIABLE _DMF_GET_ERROR)
if(NOT _DMF_GET_RESULT EQUAL 0 OR NOT _DMF_GET_HELP MATCHES "--package-dir" OR NOT _DMF_GET_HELP MATCHES "--license-dir")
    message(FATAL_ERROR "dmf-get must support --package-dir and --license-dir. Build/install the tools from lib/dmod, then set DMF_GET to the updated executable. Selected: ${DMF_GET}")
endif()

# Routes tagged configuration entries in *.dmd files ("driver=", "rules=", "service=")
# to their own subdirectory under DMBOOT_CONFIG_DIR, instead of all landing together.
# The ';' separators must be escaped: an unescaped ';' makes CMake treat this
# as a 3-element list, which add_custom_command() then expands into 3 separate
# command-line arguments instead of a single "--config-map <value>" pair.
set(DMBOOT_CONFIG_MAP "driver:${DMBOOT_CONFIG_DIR}/drivers\;rules:${DMBOOT_CONFIG_DIR}/rules\;service:${DMBOOT_CONFIG_DIR}/services")

# Applications may ship views (.dmv - the "views" resource of the module's .dmr).
# dmf-get installs them into <views dir>/<module>: views of the flash modules go to
# DMBOOT_EVIEWS_DIR (embedded and mounted as /eviews/, see scripts/romfs.cmake),
# views of the sdcard modules stay on the sdcard, in DMBOOT_SDCARD_VIEWS_DIR.
file(MAKE_DIRECTORY "${DMBOOT_EVIEWS_DIR}" "${DMBOOT_LICENSE_DIR}")

# Package contents stay on the host, outside the directories embedded as binaries
# or uploaded to the card. Download markers must not pollute binary directories.
set(DMBOOT_FLASH_PACKAGE_DIR "${CMAKE_BINARY_DIR}/packages/flash")
set(DMBOOT_SDCARD_PACKAGE_DIR "${CMAKE_BINARY_DIR}/packages/sdcard")
set(DMBOOT_MODULE_OUTPUT_SCRIPT "${CMAKE_SOURCE_DIR}/scripts/module_output.cmake")

# Units and rules of the board itself (configs/board/<BOARD>/services|rules, and ext/services|rules when the board has an
# external flash) - e.g. what is mounted where. The ones of the modules come with their packages (service= / rules= above). They land next to those
# (services/board/, rules/board/); configure_file() copies them again whenever one changes and the list is a
# dependency of the config filesystem image (see scripts/romfs.cmake).
set(DMBOOT_BOARD_CONFIG_FILES "")
if(BOARD)
    set(_board_config_dirs "${CMAKE_SOURCE_DIR}/configs/board/${BOARD}")
    if(DMBOOT_EXT_DEVICE)
        list(APPEND _board_config_dirs "${CMAKE_SOURCE_DIR}/configs/board/${BOARD}/ext")
    endif()
    foreach(_kind IN ITEMS services rules)
      foreach(_board_dir IN LISTS _board_config_dirs)
        file(GLOB _board_files CONFIGURE_DEPENDS "${_board_dir}/${_kind}/*")
        foreach(_board_file IN LISTS _board_files)
            get_filename_component(_board_name "${_board_file}" NAME)
            configure_file("${_board_file}" "${DMBOOT_CONFIG_DIR}/${_kind}/board/${_board_name}" COPYONLY)
            list(APPEND DMBOOT_BOARD_CONFIG_FILES "${_board_file}")
        endforeach()
      endforeach()
    endforeach()
endif()
set(DMBOOT_BOARD_CONFIG_FILES "${DMBOOT_BOARD_CONFIG_FILES}" PARENT_SCOPE)

set(DMBOOT_MODULES_OUT_DIR "${CMAKE_BINARY_DIR}/dmf")
set(DMBOOT_MODULES_MARKER_FILE "${CMAKE_CURRENT_BINARY_DIR}/flash.download_complete")
# scripts/romfs.cmake keys the config filesystem image off this marker: dmf-get
# drops each module's service=/rules= files into DMBOOT_CONFIG_DIR's existing
# subdirectories, which leaves that directory's own mtime untouched, so a
# directory-only dependency silently ships a stale config_fs.dmffs.
set(DMBOOT_MODULES_MARKER_FILE "${DMBOOT_MODULES_MARKER_FILE}" PARENT_SCOPE)

# The .dmd format (comments, $include, $from, versions, config files, variable
# substitution, ...) is understood by dmf-get itself - we don't re-implement
# any of that parsing here. Instead we generate one combined .dmd file that
# $includes every real flash.dmd file and additionally lists the main module
# and the shell module as plain entries, then hand the whole thing to a single
# dmf-get invocation. If a module is already present in one of the included
# files, dmf-get simply resolves/downloads it again for that entry (the .dmd
# format explicitly supports a module appearing more than once, e.g. to pull
# a config from a different version - see docs/dmd-file-format.md).
set(DMBOOT_COMBINED_FLASH_DMD "${CMAKE_BINARY_DIR}/combined_flash.dmd")

set(_COMBINED_FLASH_DMD_CONTENT "# Auto-generated by CMake - do not edit\n")
foreach(_DMD_FILE IN LISTS DMBOOT_FLASH_DMD_FILES)
    string(APPEND _COMBINED_FLASH_DMD_CONTENT "$include ${_DMD_FILE}\n")
endforeach()
if(DMBOOT_MAIN_MODULE)
    set(_MAIN_MODULE_ENTRY "${DMBOOT_MAIN_MODULE}")
    if(DMBOOT_MAIN_MODULE_CONFIG)
        string(APPEND _MAIN_MODULE_ENTRY " ${DMBOOT_MAIN_MODULE_CONFIG}")
    endif()
    string(APPEND _COMBINED_FLASH_DMD_CONTENT "${_MAIN_MODULE_ENTRY}\n")
endif()
# Shell module is only added as its own entry when it differs from the main
# module, to avoid an unnecessary duplicate download of the exact same entry
if(DMBOOT_SHELL AND NOT DMBOOT_SHELL STREQUAL DMBOOT_MAIN_MODULE)
    string(APPEND _COMBINED_FLASH_DMD_CONTENT "${DMBOOT_SHELL}\n")
endif()

if(DMBOOT_FLASH_DMD_FILES OR DMBOOT_MAIN_MODULE OR DMBOOT_SHELL)
    file(WRITE "${DMBOOT_COMBINED_FLASH_DMD}" "${_COMBINED_FLASH_DMD_CONTENT}")

    set(_FLASH_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -DMODULE_DIR=${DMBOOT_MODULES_OUT_DIR} -DPACKAGE_DIR=${DMBOOT_FLASH_PACKAGE_DIR} -P "${DMBOOT_MODULE_OUTPUT_SCRIPT}"
    )
    if(DMBOOT_MANIFEST_URL)
        list(APPEND _FLASH_DOWNLOAD_COMMANDS
            COMMAND ${CMAKE_COMMAND} -E echo "Downloading flash modules (manifest: ${DMBOOT_MANIFEST_URL})..."
            COMMAND ${DMF_GET} -d "${DMBOOT_COMBINED_FLASH_DMD}" -m "${DMBOOT_MANIFEST_URL}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type "${DMBOOT_MODULE_TYPE}" --config-dir "${DMBOOT_CONFIG_DIR}" --config-map "${DMBOOT_CONFIG_MAP}" --views-dir "${DMBOOT_EVIEWS_DIR}" --package-dir "${DMBOOT_FLASH_PACKAGE_DIR}" --license-dir "${DMBOOT_LICENSE_DIR}"
        )
    else()
        list(APPEND _FLASH_DOWNLOAD_COMMANDS
            COMMAND ${CMAKE_COMMAND} -E echo "Downloading flash modules..."
            COMMAND ${DMF_GET} -d "${DMBOOT_COMBINED_FLASH_DMD}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type "${DMBOOT_MODULE_TYPE}" --config-dir "${DMBOOT_CONFIG_DIR}" --config-map "${DMBOOT_CONFIG_MAP}" --views-dir "${DMBOOT_EVIEWS_DIR}" --package-dir "${DMBOOT_FLASH_PACKAGE_DIR}" --license-dir "${DMBOOT_LICENSE_DIR}"
        )
    endif()
    if(DMBOOT_EMULATION)
        # Renode's USART cannot be served by DMA: the UARTs receive by interrupt
        list(APPEND _FLASH_DOWNLOAD_COMMANDS
            COMMAND ${CMAKE_COMMAND} -DDMUART_CONFIG_DIR=${DMBOOT_CONFIG_DIR}/drivers/dmuart
                -P "${CMAKE_SOURCE_DIR}/scripts/emulation_uart_config.cmake"
        )
    endif()
    list(APPEND _FLASH_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -DMODULE_DIR=${DMBOOT_MODULES_OUT_DIR} -DCHECK_ONLY=ON -P "${DMBOOT_MODULE_OUTPUT_SCRIPT}"
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_MODULES_MARKER_FILE}"
    )

    add_custom_command(
        OUTPUT "${DMBOOT_MODULES_MARKER_FILE}"
        ${_FLASH_DOWNLOAD_COMMANDS}
        DEPENDS ${DMBOOT_FLASH_DMD_FILES} "${DMBOOT_COMBINED_FLASH_DMD}" "${DMF_GET}" "${DMBOOT_MODULE_OUTPUT_SCRIPT}" "${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt"
        COMMENT "Downloading flash modules from: ${DMBOOT_FLASH_DMD_FILES}; main module: ${DMBOOT_MAIN_MODULE}; shell: ${DMBOOT_SHELL}"
        VERBATIM
    )
    add_custom_target(download_modules ALL
        DEPENDS "${DMBOOT_MODULES_MARKER_FILE}"
    )
    message(STATUS "Flash DMD files: ${DMBOOT_FLASH_DMD_FILES}")
    message(STATUS "Main module: ${DMBOOT_MAIN_MODULE}")
    message(STATUS "Shell module: ${DMBOOT_SHELL}")
else()
    message(WARNING "No flash.dmd files, main module, or shell module configured. Skipping flash module download.")
    add_custom_target(download_modules ALL)
endif()

# ======================================================================
#               Downloading sdcard modules
# ======================================================================
set(DMBOOT_SDCARD_OUT_DIR "${CMAKE_BINARY_DIR}/sdcard")
# Both module formats (.dmf and .dmfc) go to bin on the card. Keep views
# beside bin, so upload-files preserves their existing paths.
set(DMBOOT_SDCARD_BIN_DIR "${DMBOOT_SDCARD_OUT_DIR}/bin")
set(DMBOOT_SDCARD_MARKER_FILE "${CMAKE_CURRENT_BINARY_DIR}/sdcard.download_complete")
set(DMBOOT_SDCARD_VIEWS_DIR "${DMBOOT_SDCARD_OUT_DIR}/views")
set(DMBOOT_SDCARD_LICENSE_DIR "${DMBOOT_SDCARD_OUT_DIR}/lic")

if(DMBOOT_SDCARD_DMD_FILES)
    set(_SDCARD_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -DMODULE_DIR=${DMBOOT_SDCARD_BIN_DIR} -DPACKAGE_DIR=${DMBOOT_SDCARD_PACKAGE_DIR} -P "${DMBOOT_MODULE_OUTPUT_SCRIPT}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_SDCARD_LICENSE_DIR}"
    )
    foreach(_DMD_FILE IN LISTS DMBOOT_SDCARD_DMD_FILES)
        set(_EFFECTIVE_MANIFEST "${DMBOOT_MANIFEST_URL}")
        if(_EFFECTIVE_MANIFEST)
            list(APPEND _SDCARD_DOWNLOAD_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E echo "Downloading sdcard modules from ${_DMD_FILE} (manifest: ${_EFFECTIVE_MANIFEST})..."
                COMMAND ${DMF_GET} -d "${_DMD_FILE}" -m "${_EFFECTIVE_MANIFEST}" -o "${DMBOOT_SDCARD_BIN_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type "${DMBOOT_MODULE_TYPE}" --config-dir "${DMBOOT_CONFIG_DIR}" --config-map "${DMBOOT_CONFIG_MAP}" --views-dir "${DMBOOT_SDCARD_VIEWS_DIR}" --package-dir "${DMBOOT_SDCARD_PACKAGE_DIR}" --license-dir "${DMBOOT_SDCARD_LICENSE_DIR}"
            )
        else()
            list(APPEND _SDCARD_DOWNLOAD_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E echo "Downloading sdcard modules from ${_DMD_FILE}..."
                COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_SDCARD_BIN_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type "${DMBOOT_MODULE_TYPE}" --config-dir "${DMBOOT_CONFIG_DIR}" --config-map "${DMBOOT_CONFIG_MAP}" --views-dir "${DMBOOT_SDCARD_VIEWS_DIR}" --package-dir "${DMBOOT_SDCARD_PACKAGE_DIR}" --license-dir "${DMBOOT_SDCARD_LICENSE_DIR}"
            )
        endif()
    endforeach()
    list(APPEND _SDCARD_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -DMODULE_DIR=${DMBOOT_SDCARD_BIN_DIR} -DCHECK_ONLY=ON -P "${DMBOOT_MODULE_OUTPUT_SCRIPT}"
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_SDCARD_MARKER_FILE}"
    )

    add_custom_command(
        OUTPUT "${DMBOOT_SDCARD_MARKER_FILE}"
        ${_SDCARD_DOWNLOAD_COMMANDS}
        DEPENDS ${DMBOOT_SDCARD_DMD_FILES} "${DMF_GET}" "${DMBOOT_MODULE_OUTPUT_SCRIPT}" "${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt"
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
#               Downloading ext modules
# ======================================================================
# Like the sdcard modules: the modules (.dmf/.dmfc) go to bin, the views and licenses beside it, the rest of the packages
# stays on the host (build/packages/ext). The directory is what the external flash holds below /ext: upload-ext sends
# build/ext as it is.
set(DMBOOT_EXT_OUT_DIR "${CMAKE_BINARY_DIR}/ext")
set(DMBOOT_EXT_BIN_DIR "${DMBOOT_EXT_OUT_DIR}/bin")
set(DMBOOT_EXT_PACKAGE_DIR "${CMAKE_BINARY_DIR}/packages/ext")
set(DMBOOT_EXT_MARKER_FILE "${CMAKE_CURRENT_BINARY_DIR}/ext.download_complete")
set(DMBOOT_EXT_VIEWS_DIR "${DMBOOT_EXT_OUT_DIR}/views")
set(DMBOOT_EXT_LICENSE_DIR "${DMBOOT_EXT_OUT_DIR}/lic")

if(DMBOOT_EXT_DMD_FILES)
    set(_EXT_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -DMODULE_DIR=${DMBOOT_EXT_BIN_DIR} -DPACKAGE_DIR=${DMBOOT_EXT_PACKAGE_DIR} -P "${DMBOOT_MODULE_OUTPUT_SCRIPT}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_EXT_LICENSE_DIR}"
    )
    foreach(_DMD_FILE IN LISTS DMBOOT_EXT_DMD_FILES)
        set(_EFFECTIVE_MANIFEST "${DMBOOT_MANIFEST_URL}")
        if(_EFFECTIVE_MANIFEST)
            list(APPEND _EXT_DOWNLOAD_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E echo "Downloading ext modules from ${_DMD_FILE} (manifest: ${_EFFECTIVE_MANIFEST})..."
                COMMAND ${DMF_GET} -d "${_DMD_FILE}" -m "${_EFFECTIVE_MANIFEST}" -o "${DMBOOT_EXT_BIN_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type "${DMBOOT_MODULE_TYPE}" --config-dir "${DMBOOT_CONFIG_DIR}" --config-map "${DMBOOT_CONFIG_MAP}" --views-dir "${DMBOOT_EXT_VIEWS_DIR}" --package-dir "${DMBOOT_EXT_PACKAGE_DIR}" --license-dir "${DMBOOT_EXT_LICENSE_DIR}"
            )
        else()
            list(APPEND _EXT_DOWNLOAD_COMMANDS
                COMMAND ${CMAKE_COMMAND} -E echo "Downloading ext modules from ${_DMD_FILE}..."
                COMMAND ${DMF_GET} -d "${_DMD_FILE}" -o "${DMBOOT_EXT_BIN_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type "${DMBOOT_MODULE_TYPE}" --config-dir "${DMBOOT_CONFIG_DIR}" --config-map "${DMBOOT_CONFIG_MAP}" --views-dir "${DMBOOT_EXT_VIEWS_DIR}" --package-dir "${DMBOOT_EXT_PACKAGE_DIR}" --license-dir "${DMBOOT_EXT_LICENSE_DIR}"
            )
        endif()
    endforeach()
    list(APPEND _EXT_DOWNLOAD_COMMANDS
        COMMAND ${CMAKE_COMMAND} -DMODULE_DIR=${DMBOOT_EXT_BIN_DIR} -DCHECK_ONLY=ON -P "${DMBOOT_MODULE_OUTPUT_SCRIPT}"
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_EXT_MARKER_FILE}"
    )

    add_custom_command(
        OUTPUT "${DMBOOT_EXT_MARKER_FILE}"
        ${_EXT_DOWNLOAD_COMMANDS}
        DEPENDS ${DMBOOT_EXT_DMD_FILES} "${DMF_GET}" "${DMBOOT_MODULE_OUTPUT_SCRIPT}" "${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt"
        COMMENT "Downloading ext modules from: ${DMBOOT_EXT_DMD_FILES}"
        VERBATIM
    )
    add_custom_target(download_ext_modules ALL
        DEPENDS "${DMBOOT_EXT_MARKER_FILE}"
    )
    message(STATUS "Ext DMD files: ${DMBOOT_EXT_DMD_FILES}")
else()
    message(STATUS "No ext.dmd files found. Skipping ext module download.")
    add_custom_target(download_ext_modules ALL)
endif()

# ======================================================================
#               Preparing dmp file from flash modules
# ======================================================================
find_program(TODMP todmp HINTS ${DMBOOT_TOOLS_DIR})
if(NOT TODMP)
    message(FATAL_ERROR "todmp tool not found. Please build and install dmod tools first.")
endif()
set(DMBOOT_MODULES_DMP "${CMAKE_BINARY_DIR}/modules.dmp")

# When a main module is expected, fail the build if no .dmf/.dmfc files are found
# after the download step. Otherwise, just print a notice and succeed.
if(DMBOOT_MAIN_MODULE)
    add_custom_command(
        OUTPUT "${DMBOOT_MODULES_DMP}"
        WORKING_DIRECTORY ${DMBOOT_MODULES_OUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E echo "Checking if modules directory contains files..."
        COMMAND ${CMAKE_COMMAND} -E echo "Contents of ${DMBOOT_MODULES_OUT_DIR}:"
        COMMAND ls -la ${DMBOOT_MODULES_OUT_DIR} || ${CMAKE_COMMAND} -E echo "Directory is empty or does not exist"
        COMMAND bash -c "if compgen -G '${DMBOOT_MODULES_OUT_DIR}/*.dmf' > /dev/null || compgen -G '${DMBOOT_MODULES_OUT_DIR}/*.dmfc' > /dev/null; then ${TODMP} modules ${DMBOOT_MODULES_OUT_DIR} ${DMBOOT_MODULES_DMP} ${DMBOOT_MAIN_MODULE}; ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf ${DMBOOT_MODULES_OUT_DIR}/*.dmfc 2> /dev/null || true; else echo 'ERROR: No .dmf/.dmfc files found in ${DMBOOT_MODULES_OUT_DIR} but main module ${DMBOOT_MAIN_MODULE} was expected. Module download may have failed.'; exit 1; fi"
        DEPENDS "${DMBOOT_MODULES_MARKER_FILE}" download_modules
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
        COMMAND bash -c "if compgen -G '${DMBOOT_MODULES_OUT_DIR}/*.dmf' > /dev/null || compgen -G '${DMBOOT_MODULES_OUT_DIR}/*.dmfc' > /dev/null; then ${TODMP} modules ${DMBOOT_MODULES_OUT_DIR} ${DMBOOT_MODULES_DMP}; ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf ${DMBOOT_MODULES_OUT_DIR}/*.dmfc 2> /dev/null || true; else echo 'No .dmf/.dmfc files found, skipping DMP creation'; fi"
        DEPENDS "${DMBOOT_MODULES_MARKER_FILE}" download_modules
        COMMENT "Creating modules dmp file from flash modules (if any exist)..."
        VERBATIM
    )
endif()
add_custom_target(prepare_modules_dmp ALL
    DEPENDS "${DMBOOT_MODULES_DMP}"
)
