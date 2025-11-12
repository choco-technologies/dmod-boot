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
include(configs/dmvfs-cfg.cmake)
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

target_compile_definitions(${MODULE_NAME}.elf
    PRIVATE 
        DMBOOT_MCU_SERIES=${DMBOOT_MCU_SERIES}
        DMBOOT_MCU_SERIES_STRING="${DMBOOT_MCU_SERIES}"
        DMBOOT_MCU_NAME=${DMBOOT_MCU_NAME}
        DMBOOT_MCU_NAME_STRING="${DMBOOT_MCU_NAME}"
        DMBOOT_MAX_MOUNT_POINTS=${DMBOOT_MAX_MOUNT_POINTS}
        DMBOOT_MAX_OPEN_FILES=${DMBOOT_MAX_OPEN_FILES}
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
        dmheap
        dmvfs
        dmenv
        dmboot_inc
        dmboot_startup
        dmboot_arch
)

# ======================================================================
#               Memory Report Generation
# ======================================================================
add_custom_command(
    TARGET ${MODULE_NAME}.elf POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E echo "Generating memory usage report..."
    COMMAND python3 ${CMAKE_CURRENT_SOURCE_DIR}/scripts/memory_report.py 
            ${CMAKE_BINARY_DIR}/${MODULE_NAME}.map 
            ${CMAKE_BINARY_DIR}
            --lib-dir ${CMAKE_CURRENT_SOURCE_DIR}/lib
    COMMENT "Analyzing memory usage from ${MODULE_NAME}.map"
    VERBATIM
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

# ======================================================================
#               DMLOG Monitor Tool
# ======================================================================

# Custom target to build dmlog_monitor for host architecture
set(DMLOG_HOST_BUILD_DIR ${CMAKE_CURRENT_SOURCE_DIR}/lib/dmlog/build_host)
set(DMLOG_MONITOR_EXECUTABLE ${DMLOG_HOST_BUILD_DIR}/tools/monitor/dmlog_monitor)

add_custom_command(
    OUTPUT ${DMLOG_MONITOR_EXECUTABLE}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${DMLOG_HOST_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E chdir ${DMLOG_HOST_BUILD_DIR}
        ${CMAKE_COMMAND} -DDMLOG_BUILD_TOOLS=ON ${CMAKE_CURRENT_SOURCE_DIR}/lib/dmlog
    COMMAND ${CMAKE_COMMAND} --build ${DMLOG_HOST_BUILD_DIR}
    COMMENT "Building dmlog_monitor for host architecture..."
    VERBATIM
)

add_custom_target(build_dmlog_monitor
    DEPENDS ${DMLOG_MONITOR_EXECUTABLE}
)

# Extract ring buffer configuration after building firmware
add_custom_command(
    OUTPUT ${CMAKE_BINARY_DIR}/dmlog_ring_buffer.cmake
    COMMAND python3 ${CMAKE_CURRENT_SOURCE_DIR}/scripts/extract_ring_buffer_addr.py 
            ${CMAKE_BINARY_DIR}/${MODULE_NAME}.map 
            --output ${CMAKE_BINARY_DIR}/dmlog_ring_buffer.cmake
            --format cmake
    DEPENDS ${MODULE_NAME}.elf
    COMMENT "Extracting dmlog ring buffer configuration from map file..."
    VERBATIM
)

add_custom_target(extract_ring_buffer_config
    DEPENDS ${CMAKE_BINARY_DIR}/dmlog_ring_buffer.cmake
)

# Custom target for monitoring logs via OpenOCD
add_custom_target(monitor
    COMMAND ${CMAKE_COMMAND} -E echo "Starting dmlog monitor..."
    COMMAND ${CMAKE_COMMAND} -E echo "Ring buffer address will be read from ${CMAKE_BINARY_DIR}/dmlog_ring_buffer.cmake"
    COMMAND ${CMAKE_COMMAND} 
        -DPROJECT_BINARY_DIR=${CMAKE_BINARY_DIR}
        -DPROJECT_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/scripts/run_monitor.cmake
    DEPENDS build_dmlog_monitor extract_ring_buffer_config
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Monitoring logs from ${TARGET} via OpenOCD..."
)