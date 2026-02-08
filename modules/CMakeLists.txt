# ======================================================================
#               Downloading modules from DMD 
# ======================================================================
find_program(DMF_GET dmf-get HINTS ${DMBOOT_TOOLS_DIR})
if(NOT DMF_GET)
    message(FATAL_ERROR "dmf-get tool not found. Please build and install dmod tools first.")
endif()

set(DMBOOT_MODULES_DMD "${CMAKE_CURRENT_SOURCE_DIR}/modules.dmd")
set(DMBOOT_MODULES_OUT_DIR "${CMAKE_BINARY_DIR}/dmf")
set(DMBOOT_MODULES_MARKER_FILE "${DMBOOT_MODULES_OUT_DIR}/.download_complete")
if(EXISTS "${DMBOOT_MODULES_DMD}")
    add_custom_command(
        OUTPUT "${DMBOOT_MODULES_MARKER_FILE}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_MODULES_OUT_DIR}"
        COMMAND ${CMAKE_COMMAND} -E echo "Downloading modules to ${DMBOOT_MODULES_OUT_DIR}..."
        COMMAND ${DMF_GET} -d "${DMBOOT_MODULES_DMD}" -o "${DMBOOT_MODULES_OUT_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmf
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_MODULES_MARKER_FILE}"
        DEPENDS "${DMBOOT_MODULES_DMD}"
        COMMENT "Downloading modules specified in ${DMBOOT_MODULES_DMD} from DMD..."
        VERBATIM
    )
    add_custom_target(download_modules ALL
        DEPENDS "${DMBOOT_MODULES_MARKER_FILE}"
    )
else()
    message(WARNING "Modules DMD file not found at ${DMBOOT_MODULES_DMD}. Skipping module download.")
endif()

# ======================================================================
#               Downloading configuration files from DMD 
# ======================================================================
set(DMBOOT_CONFIGS_MARKER_FILE "${DMBOOT_CONFIG_DIR}/.download_complete")
if(EXISTS "${DMBOOT_MODULES_DMD}")
    add_custom_command(
        OUTPUT "${DMBOOT_CONFIGS_MARKER_FILE}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_CONFIG_DIR}"
        COMMAND ${CMAKE_COMMAND} -E echo "Downloading configuration files to ${DMBOOT_CONFIG_DIR}..."
        COMMAND ${DMF_GET} -d "${DMBOOT_MODULES_DMD}" --config-dir "${DMBOOT_CONFIG_DIR}" -t "${DMOD_TOOLS_NAME}" --cpu-family "${DMBOOT_MCU_SERIES}" -y --type dmfc
        COMMAND ${CMAKE_COMMAND} -E touch "${DMBOOT_CONFIGS_MARKER_FILE}"
        DEPENDS "${DMBOOT_MODULES_DMD}"
        COMMENT "Downloading configuration files specified in ${DMBOOT_MODULES_DMD} from DMD..."
        VERBATIM
    )
    add_custom_target(download_configs ALL
        DEPENDS "${DMBOOT_CONFIGS_MARKER_FILE}"
    )
else()
    message(WARNING "Modules DMD file not found at ${DMBOOT_MODULES_DMD}. Skipping config download.")
endif()
        
# ======================================================================
#               Preparing dmp file from modules
# ======================================================================
find_program(TODMP todmp HINTS ${DMBOOT_TOOLS_DIR})
if(NOT TODMP)
    message(FATAL_ERROR "todmp tool not found. Please build and install dmod tools first.")
endif()
set(DMBOOT_MODULES_PACKAGE_NAME "modules")
set(DMBOOT_REQUIRED_MODULES_DMD "${DMBOOT_MODULES_DMD}")
set(DMBOOT_MODULES_DMP "${CMAKE_BINARY_DIR}/modules.dmp")

add_custom_command(
    OUTPUT "${DMBOOT_MODULES_DMP}"
    WORKING_DIRECTORY ${DMBOOT_MODULES_OUT_DIR}
    COMMAND ${CMAKE_COMMAND} -E echo "Checking if modules directory contains files..."
    COMMAND ${CMAKE_COMMAND} -E echo "Contents of ${DMBOOT_MODULES_OUT_DIR}:"
    COMMAND ls -la ${DMBOOT_MODULES_OUT_DIR} || ${CMAKE_COMMAND} -E echo "Directory is empty or does not exist"
    COMMAND bash -c "if ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf 1> /dev/null 2>&1; then ${TODMP} modules ${DMBOOT_MODULES_OUT_DIR} ${DMBOOT_MODULES_DMP} dmell; ls ${DMBOOT_MODULES_OUT_DIR}/*.dmf; else echo 'No .dmf files found'; fi"
    DEPENDS download_modules
    COMMENT "Creating modules dmp file from modules (if any exist)..."
    VERBATIM
)
add_custom_target(prepare_modules_dmp ALL
    DEPENDS "${DMBOOT_MODULES_DMP}"
)