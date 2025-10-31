# CMakeLists.txt for dmod-boot
# Minimal embedded project for STM32 microcontrollers
cmake_minimum_required(VERSION 3.15)

# Target selection (STM32F746 or STM32F407)
set(TARGET "STM32F746" CACHE STRING "Target selection (STM32F746 or STM32F407)")
set_property(CACHE TARGET PROPERTY STRINGS STM32F746 STM32F407)

# Log ring buffer configuration
set(DMOD_LOG_TOTAL_SIZE 8192 CACHE STRING "Total size of log buffer in bytes")
set(DMOD_LOG_MAX_ENTRY_SIZE 512 CACHE STRING "Maximum size of a single log entry")

# Heap size configuration for dmheap
set(DMHEAP_SIZE 32768 CACHE STRING "Size of dmheap in bytes (32KB default)")

# DMOD configuration
set(DMOD_CFG ${CMAKE_SOURCE_DIR}/dmod-cfg.cmake)

# Project definition
project(dmod-boot C ASM)

# Toolchain setup for ARM
set(CMAKE_C_COMPILER arm-none-eabi-gcc)
set(CMAKE_OBJCOPY arm-none-eabi-objcopy)
set(CMAKE_SIZE arm-none-eabi-size)
set(CMAKE_OBJDUMP arm-none-eabi-objdump)
set(CMAKE_NM arm-none-eabi-nm)

# Directories
set(SRC_DIR ${CMAKE_SOURCE_DIR}/src)
set(INC_DIR ${CMAKE_SOURCE_DIR}/include)
set(LINKER_DIR ${CMAKE_SOURCE_DIR}/linker)
set(EXAMPLES_DIR ${CMAKE_SOURCE_DIR}/examples)
set(SCRIPTS_DIR ${CMAKE_SOURCE_DIR}/scripts)

# Target-specific settings
if("${TARGET}" STREQUAL "STM32F746")
    set(LINKER_SCRIPT ${LINKER_DIR}/STM32F746xG.ld)
    set(STARTUP_SRC ${SRC_DIR}/startup_stm32f746.c)
    set(CPU cortex-m7)
    set(FPU_FLAGS "-mfpu=fpv5-sp-d16")
    set(FLOAT_ABI_FLAGS "-mfloat-abi=hard")
    set(OPENOCD_TARGET "target/stm32f7x.cfg")
elseif("${TARGET}" STREQUAL "STM32F407")
    set(LINKER_SCRIPT ${LINKER_DIR}/STM32F407xG.ld)
    set(STARTUP_SRC ${SRC_DIR}/startup_stm32f407.c)
    set(CPU cortex-m4)
    set(FPU_FLAGS "-mfpu=fpv4-sp-d16")
    set(FLOAT_ABI_FLAGS "-mfloat-abi=hard")
    set(OPENOCD_TARGET "target/stm32f4x.cfg")
else()
    message(FATAL_ERROR "Invalid TARGET. Use STM32F746 or STM32F407")
endif()

# OpenOCD settings
set(OPENOCD_INTERFACE "interface/stlink.cfg")
set(OPENOCD openocd)

# Compiler flags
set(CMAKE_C_FLAGS "-mcpu=${CPU} -mthumb ${FPU_FLAGS} ${FLOAT_ABI_FLAGS}")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -Werror")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ffunction-sections -fdata-sections")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O2 -g")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DSTM32 -D${TARGET}")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDMOD_LOG_TOTAL_SIZE=${DMOD_LOG_TOTAL_SIZE}")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDMOD_LOG_MAX_ENTRY_SIZE=${DMOD_LOG_MAX_ENTRY_SIZE}")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDMHEAP_SIZE=${DMHEAP_SIZE}")

# Linker flags
set(CMAKE_EXE_LINKER_FLAGS "-mcpu=${CPU} -mthumb ${FPU_FLAGS} ${FLOAT_ABI_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -T${LINKER_SCRIPT}")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,--gc-sections")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-Map=${CMAKE_BINARY_DIR}/${TARGET}.map")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} --specs=nosys.specs")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} --specs=nano.specs")

# Add DMOD library
add_subdirectory(lib/dmod)

# Add dmheap library
add_subdirectory(lib/dmheap)

# Source files
set(SOURCES
    ${STARTUP_SRC}
    ${SRC_DIR}/dmod_printf.c
    ${SRC_DIR}/dmod_sal_printf.c
    ${SRC_DIR}/main.c
)

# Create executable
add_executable(${TARGET}.elf ${SOURCES})

# Include directories
target_include_directories(${TARGET}.elf PRIVATE 
    ${INC_DIR}
    ${CMAKE_SOURCE_DIR}/lib/dmod/inc
    ${CMAKE_SOURCE_DIR}/lib/dmheap/include
)

# Link libraries
target_link_libraries(${TARGET}.elf PRIVATE dmod dmheap)

# Add linker scripts directory for dmod-common.ld
target_link_options(${TARGET}.elf PRIVATE -L ${CMAKE_SOURCE_DIR}/lib/dmod/scripts)

# Custom commands for binary and hex files
add_custom_command(TARGET ${TARGET}.elf POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} -O binary ${TARGET}.elf ${TARGET}.bin
    COMMAND ${CMAKE_OBJCOPY} -O ihex ${TARGET}.elf ${TARGET}.hex
    COMMENT "Creating binary and hex files"
)

# Custom command to extract addresses
add_custom_command(TARGET ${TARGET}.elf POST_BUILD
    COMMAND bash ${SCRIPTS_DIR}/extract_addresses.sh ${TARGET}.elf ${TARGET} ${DMOD_LOG_TOTAL_SIZE} ${DMOD_LOG_MAX_ENTRY_SIZE} ${TARGET}_dmod_addresses.txt
    COMMENT "Extracting symbol addresses"
)

# Display size after build
add_custom_command(TARGET ${TARGET}.elf POST_BUILD
    COMMAND ${CMAKE_SIZE} ${TARGET}.elf
    COMMENT "Displaying memory usage"
)

# Custom target for disassembly
add_custom_target(disasm
    COMMAND ${CMAKE_OBJDUMP} -d ${TARGET}.elf > ${TARGET}.dis
    DEPENDS ${TARGET}.elf
    COMMENT "Generating disassembly"
)

# Custom target for installing (flashing) firmware
add_custom_target(install-firmware
    COMMAND ${OPENOCD} -f ${OPENOCD_INTERFACE} -f ${OPENOCD_TARGET}
        -c "program ${TARGET}.elf verify reset exit"
    DEPENDS ${TARGET}.elf
    COMMENT "Installing firmware on ${TARGET}..."
)

# Custom target for connecting to target with OpenOCD
add_custom_target(connect
    COMMAND ${OPENOCD} -f ${OPENOCD_INTERFACE} -f ${OPENOCD_TARGET}
    COMMENT "Connecting to ${TARGET} with OpenOCD..."
)

# Custom target for monitoring log output
add_custom_target(monitor
    COMMAND python3 ${SCRIPTS_DIR}/dmod_log_monitor.py --target ${TARGET}
    DEPENDS ${TARGET}.elf
    COMMENT "Starting log monitor for ${TARGET}..."
)

# Print build configuration
message(STATUS "Building for target: ${TARGET}")
message(STATUS "CPU: ${CPU}")
message(STATUS "Linker script: ${LINKER_SCRIPT}")
message(STATUS "Log buffer size: ${DMOD_LOG_TOTAL_SIZE}")
message(STATUS "Max log entry size: ${DMOD_LOG_MAX_ENTRY_SIZE}")
message(STATUS "Heap size: ${DMHEAP_SIZE}")
message(STATUS "DMOD library: ${CMAKE_SOURCE_DIR}/lib/dmod")
message(STATUS "dmheap library: ${CMAKE_SOURCE_DIR}/lib/dmheap")
