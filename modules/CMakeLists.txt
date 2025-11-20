# =====================================================================
#               Modules Package Builder
# =====================================================================
# This CMake script:
# 1. Builds DMOD tools (dmf-get and todmp) in SYSTEM mode
# 2. Uses dmf-get to download modules from modules.dmd for target architecture
# 3. Packages modules using todmp
# 4. Makes the package available for embedding in firmware
# =====================================================================

set(MODULES_DMD_FILE "${CMAKE_CURRENT_SOURCE_DIR}/modules.dmd")
set(MODULES_DOWNLOAD_DIR "${CMAKE_CURRENT_BINARY_DIR}/dmf")
set(MODULES_DMP_FILE "${CMAKE_CURRENT_BINARY_DIR}/modules.dmp")

# Check if modules.dmd exists
if(NOT EXISTS "${MODULES_DMD_FILE}")
    message(STATUS "No modules.dmd file found, skipping modules package build")
    return()
endif()

# Determine target architecture for dmf-get --tools-name parameter
# dmf-get uses DMOD_TOOLS_NAME format like "arch/armv7/cortex-m4"
if(DMBOOT_ARCH STREQUAL "armv7")
    if(DMBOOT_ARCH_FAMILY STREQUAL "cortex-m4")
        set(DMOD_TARGET_TOOLS_NAME "arch/armv7/cortex-m4")
    elseif(DMBOOT_ARCH_FAMILY STREQUAL "cortex-m7")
        set(DMOD_TARGET_TOOLS_NAME "arch/armv7/cortex-m7")
    else()
        message(WARNING "Unknown ARM family: ${DMBOOT_ARCH_FAMILY}, defaulting to arch/armv7/cortex-m4")
        set(DMOD_TARGET_TOOLS_NAME "arch/armv7/cortex-m4")
    endif()
else()
    message(WARNING "Unknown architecture: ${DMBOOT_ARCH}, defaulting to arch/armv7/cortex-m4")
    set(DMOD_TARGET_TOOLS_NAME "arch/armv7/cortex-m4")
endif()

message(STATUS "Target architecture for modules: ${DMOD_TARGET_TOOLS_NAME}")

# Build DMOD tools (dmf-get and todmp) in SYSTEM mode for host architecture
set(DMOD_TOOLS_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/dmod_tools_build")
set(DMF_GET_TOOL "${DMOD_TOOLS_BUILD_DIR}/bin/tools/dmf-get")
set(TODMP_TOOL "${DMOD_TOOLS_BUILD_DIR}/bin/tools/todmp")

# Custom command to build DMOD tools
add_custom_command(
    OUTPUT "${DMF_GET_TOOL}" "${TODMP_TOOL}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${DMOD_TOOLS_BUILD_DIR}"
    COMMAND ${CMAKE_COMMAND} -E chdir "${DMOD_TOOLS_BUILD_DIR}"
        ${CMAKE_COMMAND} "${DMOD_DIR}" 
            -DDMOD_MODE=DMOD_SYSTEM 
            -DDMOD_BUILD_TOOLS=ON
            -DDMOD_TOOLS_NAME=arch/x86_64
    COMMAND ${CMAKE_COMMAND} --build "${DMOD_TOOLS_BUILD_DIR}"
    COMMENT "Building DMOD tools (dmf-get and todmp) for host architecture..."
    VERBATIM
)

add_custom_target(build_dmod_tools
    DEPENDS "${DMF_GET_TOOL}" "${TODMP_TOOL}"
)

# Custom command to download modules using dmf-get
# dmf-get reads modules.dmd and downloads modules for the target architecture
set(DOWNLOAD_STAMP "${CMAKE_CURRENT_BINARY_DIR}/modules_downloaded.stamp")

add_custom_command(
    OUTPUT "${DOWNLOAD_STAMP}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${MODULES_DOWNLOAD_DIR}"
    COMMAND ${CMAKE_COMMAND} -E echo "Downloading modules from modules.dmd using dmf-get..."
    COMMAND ${CMAKE_COMMAND} -E chdir "${MODULES_DOWNLOAD_DIR}"
        "${DMF_GET_TOOL}" --file "${MODULES_DMD_FILE}" --tools-name "${DMOD_TARGET_TOOLS_NAME}" --type dmf
    COMMAND ${CMAKE_COMMAND} -E touch "${DOWNLOAD_STAMP}"
    DEPENDS "${DMF_GET_TOOL}" "${MODULES_DMD_FILE}"
    COMMENT "Downloading modules for ${DMOD_TARGET_TOOLS_NAME}..."
    VERBATIM
)

add_custom_target(download_modules
    DEPENDS "${DOWNLOAD_STAMP}"
)

# Custom command to package modules using todmp
add_custom_command(
    OUTPUT "${MODULES_DMP_FILE}"
    COMMAND ${CMAKE_COMMAND} -E echo "Packaging modules with todmp..."
    COMMAND "${TODMP_TOOL}" modules_package "${MODULES_DOWNLOAD_DIR}" "${MODULES_DMP_FILE}"
    DEPENDS "${TODMP_TOOL}" "${DOWNLOAD_STAMP}"
    COMMENT "Creating modules.dmp package..."
    VERBATIM
)

add_custom_target(build_modules_package
    DEPENDS "${MODULES_DMP_FILE}"
)

# Make the modules DMP file available to the parent scope
set(MODULES_DMP_FILE "${MODULES_DMP_FILE}" PARENT_SCOPE)

message(STATUS "Modules package will be created at: ${MODULES_DMP_FILE}")
