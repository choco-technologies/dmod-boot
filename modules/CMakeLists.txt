# =====================================================================
#               DMOD Modules Build Configuration
# =====================================================================
cmake_minimum_required(VERSION 3.18)

# This directory builds DMOD modules with -DDMOD_MODE=DMOD_MODULE
# The modules are then packaged into modules.dmp using todmp tool

project(dmod_modules 
    VERSION 1.0
    DESCRIPTION "DMOD Modules Package"
    LANGUAGES C CXX)

# ======================================================================
#               Configuration
# ======================================================================
# Ensure DMOD_MODE is set to MODULE mode for all modules built here
set(DMOD_MODE "DMOD_MODULE" CACHE STRING "DMOD build mode" FORCE)

# ======================================================================
#               Add Module Subdirectories
# ======================================================================
add_subdirectory(dmffs)

# ======================================================================
#               Package Modules into DMP
# ======================================================================
# Find todmp tool
find_program(TODMP_EXECUTABLE todmp)
if(NOT TODMP_EXECUTABLE)
    message(FATAL_ERROR "todmp tool not found. Please ensure it's in PATH or build it from dmod repository.")
endif()

# Create modules.dmp package from built modules
set(MODULES_DMP_OUTPUT "${CMAKE_BINARY_DIR}/modules.dmp")
set(MODULES_DMF_DIR "${CMAKE_BINARY_DIR}/dmf")

add_custom_target(package_modules ALL
    COMMAND ${TODMP_EXECUTABLE} modules ${MODULES_DMF_DIR} ${MODULES_DMP_OUTPUT}
    DEPENDS dmffs
    COMMENT "Packaging modules into modules.dmp..."
    VERBATIM
)

# Make modules.dmp available to parent project
set(MODULES_DMP_FILE ${MODULES_DMP_OUTPUT} PARENT_SCOPE)
