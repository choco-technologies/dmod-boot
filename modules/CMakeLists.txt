# =====================================================================
#               Modules Package Builder
# =====================================================================
# This CMake script:
# 1. Reads module list from modules.dmd
# 2. Downloads modules for target architecture using dmf-get
# 3. Packages them using todmp
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

# Read and parse modules.dmd file
file(STRINGS "${MODULES_DMD_FILE}" MODULES_LIST)

# Filter out empty lines and comments
set(MODULES_TO_FETCH "")
foreach(LINE ${MODULES_LIST})
    string(STRIP "${LINE}" LINE_STRIPPED)
    if(NOT LINE_STRIPPED STREQUAL "" AND NOT LINE_STRIPPED MATCHES "^#")
        list(APPEND MODULES_TO_FETCH "${LINE_STRIPPED}")
    endif()
endforeach()

# If no modules to fetch, skip
if(NOT MODULES_TO_FETCH)
    message(STATUS "No modules found in modules.dmd")
    return()
endif()

list(LENGTH MODULES_TO_FETCH MODULES_COUNT)
message(STATUS "Found ${MODULES_COUNT} modules to fetch from modules.dmd")

# Determine target architecture for dmf-get
# Map DMBOOT_ARCH to dmf-get architecture names
if(DMBOOT_ARCH STREQUAL "armv7")
    if(DMBOOT_ARCH_FAMILY STREQUAL "cortex-m4")
        set(DMF_ARCH "arch/armv7/cortex-m4")
    elseif(DMBOOT_ARCH_FAMILY STREQUAL "cortex-m7")
        set(DMF_ARCH "arch/armv7/cortex-m7")
    else()
        message(WARNING "Unknown ARM family: ${DMBOOT_ARCH_FAMILY}, defaulting to arch/armv7/cortex-m4")
        set(DMF_ARCH "arch/armv7/cortex-m4")
    endif()
else()
    message(WARNING "Unknown architecture: ${DMBOOT_ARCH}, defaulting to arch/armv7/cortex-m4")
    set(DMF_ARCH "arch/armv7/cortex-m4")
endif()

message(STATUS "Target architecture for modules: ${DMF_ARCH}")

# First, we need to build dmod tools (todmp) in SYSTEM mode
set(DMOD_TOOLS_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/dmod_tools_build")
set(TODMP_TOOL "${DMOD_TOOLS_BUILD_DIR}/bin/tools/todmp")

# Custom command to build todmp tool
add_custom_command(
    OUTPUT "${TODMP_TOOL}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${DMOD_TOOLS_BUILD_DIR}"
    COMMAND ${CMAKE_COMMAND} -E chdir "${DMOD_TOOLS_BUILD_DIR}"
        ${CMAKE_COMMAND} "${DMOD_DIR}" 
            -DDMOD_MODE=DMOD_SYSTEM 
            -DDMOD_BUILD_TOOLS=ON
            -DDMOD_TOOLS_NAME=arch/x86_64
    COMMAND ${CMAKE_COMMAND} --build "${DMOD_TOOLS_BUILD_DIR}"
    COMMENT "Building todmp tool for host architecture..."
    VERBATIM
)

add_custom_target(build_todmp
    DEPENDS "${TODMP_TOOL}"
)

# Create download directory
add_custom_command(
    OUTPUT "${MODULES_DOWNLOAD_DIR}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${MODULES_DOWNLOAD_DIR}"
    COMMENT "Creating modules download directory..."
)

# Custom command to download modules using dmf-get
set(DOWNLOAD_STAMP "${CMAKE_CURRENT_BINARY_DIR}/modules_downloaded.stamp")

add_custom_command(
    OUTPUT "${DOWNLOAD_STAMP}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${MODULES_DOWNLOAD_DIR}"
    COMMAND ${CMAKE_COMMAND} -E echo "Downloading modules for ${DMF_ARCH}..."
    # Download each module
    COMMAND ${CMAKE_COMMAND} -E env DMOD_DMF_DIR="${MODULES_DOWNLOAD_DIR}"
        ${CMAKE_COMMAND} -P "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/download_modules.cmake"
        "${MODULES_DMD_FILE}" "${DMF_ARCH}" "${MODULES_DOWNLOAD_DIR}"
    COMMAND ${CMAKE_COMMAND} -E touch "${DOWNLOAD_STAMP}"
    DEPENDS "${MODULES_DMD_FILE}"
    COMMENT "Downloading modules from modules.dmd for ${DMF_ARCH}..."
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
