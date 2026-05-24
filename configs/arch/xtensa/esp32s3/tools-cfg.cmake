# ======================================================================
#               Toolchain configuration for Xtensa ESP32-S3
#
# This file is a local override that is consulted by CMakeLists.txt
# before falling back to the dmod library's tools-cfg.cmake.  It sets
# the cross-compilation toolchain for the Espressif xtensa-esp32s3-elf
# toolchain.
# ======================================================================

set(CMAKE_SYSTEM_NAME  Generic)
set(CMAKE_SYSTEM_PROCESSOR xtensa)

set(_XTENSA_TOOLCHAIN_HINTS
	/tools/esp-tools/xtensa-esp32s3-elf/bin
	/tools/esp-tools/xtensa-esp-elf/bin
	$ENV{HOME}/.espressif/tools/xtensa-esp-elf/bin
)

if(DEFINED ENV{ESP_TOOLCHAIN_BIN} AND NOT "$ENV{ESP_TOOLCHAIN_BIN}" STREQUAL "")
	list(PREPEND _XTENSA_TOOLCHAIN_HINTS "$ENV{ESP_TOOLCHAIN_BIN}")
endif()

if(DEFINED ENV{ESP_TOOLCHAIN_DIR} AND NOT "$ENV{ESP_TOOLCHAIN_DIR}" STREQUAL "")
	list(PREPEND _XTENSA_TOOLCHAIN_HINTS "$ENV{ESP_TOOLCHAIN_DIR}/bin")
endif()

find_program(XTENSA_GCC
	NAMES xtensa-esp32s3-elf-gcc xtensa-esp-elf-gcc
	HINTS ${_XTENSA_TOOLCHAIN_HINTS}
	REQUIRED
)

find_program(XTENSA_GXX
	NAMES xtensa-esp32s3-elf-g++ xtensa-esp-elf-g++
	HINTS ${_XTENSA_TOOLCHAIN_HINTS}
	REQUIRED
)

set(CMAKE_C_COMPILER   "${XTENSA_GCC}")
set(CMAKE_CXX_COMPILER "${XTENSA_GXX}")
set(CMAKE_ASM_COMPILER "${XTENSA_GCC}")

find_program(CMAKE_OBJCOPY
	NAMES xtensa-esp32s3-elf-objcopy xtensa-esp-elf-objcopy
	HINTS ${_XTENSA_TOOLCHAIN_HINTS}
	REQUIRED
)

find_program(CMAKE_OBJDUMP
	NAMES xtensa-esp32s3-elf-objdump xtensa-esp-elf-objdump
	HINTS ${_XTENSA_TOOLCHAIN_HINTS}
	REQUIRED
)

find_program(CMAKE_SIZE
	NAMES xtensa-esp32s3-elf-size xtensa-esp-elf-size
	HINTS ${_XTENSA_TOOLCHAIN_HINTS}
	REQUIRED
)

# GDB binary – assigned to ARM_GDB to stay compatible with scripts/targets.cmake
find_program(ARM_GDB
	NAMES xtensa-esp32s3-elf-gdb xtensa-esp-elf-gdb gdb-multiarch gdb
	HINTS ${_XTENSA_TOOLCHAIN_HINTS}
)

if(NOT ARM_GDB)
	message(WARNING "GDB binary not found (xtensa or host). Debug helper targets may be unavailable.")
endif()

# Use call0 ABI (no register-window management) and long-call support
set(CMAKE_C_FLAGS_INIT   "-mabi=call0 -mlongcalls" CACHE INTERNAL "")
set(CMAKE_CXX_FLAGS_INIT "-mabi=call0 -mlongcalls" CACHE INTERNAL "")
set(CMAKE_ASM_FLAGS_INIT "-mabi=call0 -mlongcalls" CACHE INTERNAL "")

# Prevent CMake from testing the compiler with a simple executable
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY CACHE INTERNAL "")
