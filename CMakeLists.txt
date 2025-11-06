# =====================================================================
#               DMOD Boot CMakeLists.txt
# =====================================================================
cmake_minimum_required(VERSION 3.10)

# ======================================================================
#               Configuration
# ======================================================================
set(TARGET "STM32F746xG" CACHE STRING "Target microcontroller")

# ======================================================================
#               Early DMOD Configuration (before project())
# ======================================================================
set(DMOD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib/dmod")
include(configs/dmod-cfg.cmake)
include(configs/mcu/${TARGET}.cmake)

# Include toolchain configuration before project() to set compilers
include(${DMOD_DIR}/configs/arch/${DMBOOT_ARCH}/${DMBOOT_ARCH_FAMILY}/tools-cfg.cmake)

# ======================================================================
#               DMOD Boot Project Configuration
# ======================================================================
project(dmboot
    VERSION 1.0
    DESCRIPTION "DMOD Bootloader"
    LANGUAGES C CXX ASM)

# ======================================================================
#               Subdirectories
# ======================================================================
add_subdirectory(lib)
add_subdirectory(inc)
add_subdirectory(src)

# ======================================================================
#               dmod-boot application
# ======================================================================
set(MODULE_NAME dmboot)

add_executable(${MODULE_NAME}.elf
    src/main.c
)

target_link_options(${MODULE_NAME}.elf
    PRIVATE 
        -L${DMOD_DIR}/scripts
        -T${CMAKE_CURRENT_SOURCE_DIR}/configs/arch/${DMBOOT_ARCH}/arch.ld
        -T${CMAKE_CURRENT_SOURCE_DIR}/configs/mcu/${DMBOOT_MCU_SERIES}/${DMBOOT_MCU_NAME}.ld
        -T${CMAKE_CURRENT_SOURCE_DIR}/linker/common.ld
        -Wl,-Map=${MODULE_NAME}.map
)

target_link_libraries(${MODULE_NAME}.elf
    PRIVATE 
        dmod
        dmlog
        dmboot_inc
        dmboot_startup
)


# ======================================================================
#               OpenOCD Integration
# ======================================================================

# Generate GDB init script from template with target-specific variables
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/configs/gdb/gdb_init.gdb.in
    ${CMAKE_BINARY_DIR}/gdb_init.gdb
    @ONLY
)

add_custom_target(install-firmware
    COMMAND ${OPENOCD} -f ${OPENOCD_INTERFACE} -f ${OPENOCD_TARGET}
        -c "program ${MODULE_NAME}.elf verify reset exit"
    DEPENDS ${MODULE_NAME}.elf
    COMMENT "Installing firmware on ${TARGET}..."
)

# Custom target for connecting to target with OpenOCD
add_custom_target(connect
    COMMAND ${OPENOCD} -f ${OPENOCD_INTERFACE} -f ${OPENOCD_TARGET}
    COMMENT "Connecting to ${TARGET} with OpenOCD..."
)

# Custom target for debugging with GDB (connects to OpenOCD)
add_custom_target(debug
    COMMAND ${ARM_GDB} -x ${CMAKE_BINARY_DIR}/gdb_init.gdb ${MODULE_NAME}.elf
    DEPENDS ${MODULE_NAME}.elf
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Starting GDB and connecting to OpenOCD..."
)