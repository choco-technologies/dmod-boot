# ======================================================================
#               Toolchain configuration for Xtensa LX7 (ESP32-S3)
#
# This file is a local override that is consulted by CMakeLists.txt
# before falling back to the dmod library's tools-cfg.cmake.  It sets
# the cross-compilation toolchain for the Espressif xtensa-esp32s3-elf
# toolchain.
# ======================================================================

set(CMAKE_SYSTEM_NAME  Generic)
set(CMAKE_SYSTEM_PROCESSOR xtensa)

set(_XTENSA_TOOLCHAIN_PREFIX "xtensa-esp32s3-elf-")

set(CMAKE_C_COMPILER   ${_XTENSA_TOOLCHAIN_PREFIX}gcc)
set(CMAKE_CXX_COMPILER ${_XTENSA_TOOLCHAIN_PREFIX}g++)
set(CMAKE_ASM_COMPILER ${_XTENSA_TOOLCHAIN_PREFIX}gcc)

find_program(CMAKE_OBJCOPY  ${_XTENSA_TOOLCHAIN_PREFIX}objcopy REQUIRED)
find_program(CMAKE_OBJDUMP  ${_XTENSA_TOOLCHAIN_PREFIX}objdump REQUIRED)
find_program(CMAKE_SIZE     ${_XTENSA_TOOLCHAIN_PREFIX}size    REQUIRED)

# GDB binary – assigned to ARM_GDB to stay compatible with scripts/targets.cmake
find_program(ARM_GDB ${_XTENSA_TOOLCHAIN_PREFIX}gdb REQUIRED)

# Use call0 ABI (no register-window management) and long-call support
set(CMAKE_C_FLAGS_INIT   "-mabi=call0 -mlongcalls" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "-mabi=call0 -mlongcalls" CACHE INTERNAL "")
set(CMAKE_ASM_FLAGS_INIT "-mabi=call0 -mlongcalls" CACHE INTERNAL "")

# Prevent CMake from testing the compiler with a simple executable
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY CACHE INTERNAL "")
