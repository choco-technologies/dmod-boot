# =====================================================================
#               Download Modules Script
# =====================================================================
# This script downloads modules listed in modules.dmd using dmf-get
#
# Usage:
#   cmake -P download_modules.cmake <modules.dmd> <arch> <output_dir>
# =====================================================================

# Get command line arguments
set(MODULES_FILE "${CMAKE_ARGV3}")
set(DMF_ARCH "${CMAKE_ARGV4}")
set(OUTPUT_DIR "${CMAKE_ARGV5}")

if(NOT EXISTS "${MODULES_FILE}")
    message(FATAL_ERROR "Modules file not found: ${MODULES_FILE}")
endif()

if(NOT DMF_ARCH)
    message(FATAL_ERROR "Architecture not specified")
endif()

if(NOT OUTPUT_DIR)
    message(FATAL_ERROR "Output directory not specified")
endif()

# Read modules from file
file(STRINGS "${MODULES_FILE}" MODULES_LIST)

# Process each module
foreach(LINE ${MODULES_LIST})
    string(STRIP "${LINE}" LINE_STRIPPED)
    
    # Skip empty lines and comments
    if(LINE_STRIPPED STREQUAL "" OR LINE_STRIPPED MATCHES "^#")
        continue()
    endif()
    
    message(STATUS "Processing module: ${LINE_STRIPPED}")
    
    # Parse module specification (e.g., "dmffs@1.1" -> name: dmffs, version: 1.1)
    string(REGEX MATCH "^([^@]+)(@(.+))?$" MATCH_RESULT "${LINE_STRIPPED}")
    set(MODULE_NAME "${CMAKE_MATCH_1}")
    set(MODULE_VERSION "${CMAKE_MATCH_3}")
    
    if(NOT MODULE_NAME)
        message(WARNING "Invalid module specification: ${LINE_STRIPPED}")
        continue()
    endif()
    
    message(STATUS "Downloading module: ${MODULE_NAME}")
    if(MODULE_VERSION)
        message(STATUS "  Version: ${MODULE_VERSION}")
    endif()
    message(STATUS "  Architecture: ${DMF_ARCH}")
    
    # Find dmf-get executable
    find_program(DMF_GET_EXECUTABLE dmf-get)
    
    if(NOT DMF_GET_EXECUTABLE)
        message(WARNING "dmf-get not found in PATH. Module downloads will be skipped.")
        message(WARNING "Make sure dmf-get is installed or use the Docker container.")
        return()
    endif()
    
    # Build dmf-get command
    set(DMF_GET_CMD "${DMF_GET_EXECUTABLE}" "${MODULE_NAME}")
    
    if(MODULE_VERSION)
        list(APPEND DMF_GET_CMD "--version" "${MODULE_VERSION}")
    endif()
    
    list(APPEND DMF_GET_CMD "--type" "dmf" "--arch" "${DMF_ARCH}")
    
    # Execute dmf-get
    execute_process(
        COMMAND ${DMF_GET_CMD}
        WORKING_DIRECTORY "${OUTPUT_DIR}"
        RESULT_VARIABLE RESULT
        OUTPUT_VARIABLE OUTPUT
        ERROR_VARIABLE ERROR
    )
    
    if(NOT RESULT EQUAL 0)
        message(WARNING "Failed to download module ${MODULE_NAME}: ${ERROR}")
    else()
        message(STATUS "Successfully downloaded ${MODULE_NAME}")
    endif()
endforeach()

message(STATUS "Module download complete")
