cmake_minimum_required(VERSION 3.18)
# The SDK the firmware itself is built with
if(NOT DEFINED DMOD_DIR)
    set(DMOD_DIR "${CMAKE_CURRENT_LIST_DIR}/../../lib/dmod")
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT DEFINED DMOD_MODULE_VERSION)
    set(DMOD_MODULE_VERSION "0.1" CACHE STRING "DMOD module version")
endif()

set(DMOD_MODE "DMOD_MODULE" CACHE STRING "DMOD build mode")
set(DMOD_BUILD_TESTS OFF CACHE BOOL "Build tests")
set(DMOD_BUILD_EXAMPLES OFF CACHE BOOL "Build examples")
set(DMOD_BUILD_TOOLS OFF CACHE BOOL "Build tools")
set(DMOD_BUILD_TEMPLATES OFF CACHE BOOL "Build templates")
option(DMOD_USE_INSTALLED_SDK "Use an installed dmod-dev SDK when available" ON)

# Explicit source paths take precedence over an installed SDK. Resolve DMOD
# before project() so DMOD_TOOLS_NAME can select the compiler in either flow.
set(_dmod_installed_sdk FALSE)
if(DMOD_USE_INSTALLED_SDK AND DMOD_MODE STREQUAL "DMOD_MODULE"
        AND NOT DMOD_DIR AND NOT FETCHCONTENT_SOURCE_DIR_DMOD)
    find_package(dmod CONFIG QUIET)
    if(dmod_FOUND)
        set(_dmod_installed_sdk TRUE)
    endif()
endif()

if(NOT _dmod_installed_sdk)
    if(DEFINED DMOD_DIR AND NOT "${DMOD_DIR}" STREQUAL "")
        set(FETCHCONTENT_SOURCE_DIR_DMOD "${DMOD_DIR}" CACHE PATH "" FORCE)
    endif()
    include(FetchContent)
    FetchContent_Declare(
        dmod
        GIT_REPOSITORY https://github.com/choco-technologies/dmod.git
        GIT_TAG        develop
    )
    FetchContent_MakeAvailable(dmod)
endif()

project(faulttest VERSION ${DMOD_MODULE_VERSION}
    DESCRIPTION "faulttest DMOD application module"
    LANGUAGES C CXX)

if(NOT _dmod_installed_sdk)
    set(DMOD_DIR "${dmod_SOURCE_DIR}" CACHE PATH "DMOD source directory")
    set(DMOD_SCRIPTS_DIR "${DMOD_DIR}/scripts" CACHE PATH "DMOD scripts directory")
    include("${DMOD_DIR}/paths.cmake")
    dmod_setup_external_module()
endif()

# Name of the module
set(DMOD_MODULE_NAME        faulttest)

# Author (should be string)
set(DMOD_AUTHOR_NAME        "Patryk Kubiak")

# Stack size for the module (should be integer)
set(DMOD_STACK_SIZE         2048)

# Priority for the thread of the module (should be integer)
set(DMOD_PRIORITY           0)

# List of MAL interfaces implemented by this module (leave empty if none)
set(DMOD_MAL_IMPLS          )

#
#   dmod_add_executable - create an executable module
#   it has the same signature as add_executable,
#   and can be used in the same way after the creation
#   (for example, to link libraries)
#
dmod_add_executable(${DMOD_MODULE_NAME} ${DMOD_MODULE_VERSION}
    # List of source files - can include C and C++ files
    src/faulttest.c
)

# To depend on another module's headers, use:
#   dmod_link_modules(${DMOD_MODULE_NAME}
#       other_module@1.0
#   )

