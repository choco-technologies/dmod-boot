# =====================================================================
#               DMOD Boot CMakeLists.txt
# =====================================================================
cmake_minimum_required(VERSION 3.10)

# ======================================================================
#               Configuration
# ======================================================================
set(TARGET "STM32F746xG" CACHE STRING "Target microcontroller")
set(STARTUP_DMP_FILE "" CACHE FILEPATH "Optional startup.dmp file to embed in ROM")
set(USER_DATA_FILE "" CACHE FILEPATH "Optional user_data file to embed in ROM")
option(DMBOOT_EMULATION "Enable Renode emulation mode" OFF)

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
add_subdirectory(modules)

# ======================================================================
#               Binary File Embedding
# ======================================================================
include(scripts/embed_binary.cmake)

# List to hold embedded object files
set(EMBEDDED_OBJECTS "")

# Embed startup.dmp if provided
if(STARTUP_DMP_FILE AND EXISTS "${STARTUP_DMP_FILE}")
    embed_binary_file(
        INPUT_FILE "${STARTUP_DMP_FILE}"
        SECTION_NAME ".embedded.startup_dmp"
        SYMBOL_PREFIX "__startup_dmp"
    )
    set(STARTUP_DMP_OBJECT "${CMAKE_BINARY_DIR}/__startup_dmp.o")
    list(APPEND EMBEDDED_OBJECTS "${STARTUP_DMP_OBJECT}")
    message(STATUS "Startup DMP file will be embedded: ${STARTUP_DMP_FILE}")
else()
    message(STATUS "No startup DMP file provided (STARTUP_DMP_FILE not set or file doesn't exist)")
endif()

# Embed user_data if provided
if(USER_DATA_FILE AND EXISTS "${USER_DATA_FILE}")
    embed_binary_file(
        INPUT_FILE "${USER_DATA_FILE}"
        SECTION_NAME ".embedded.user_data"
        SYMBOL_PREFIX "__user_data"
    )
    set(USER_DATA_OBJECT "${CMAKE_BINARY_DIR}/__user_data.o")
    list(APPEND EMBEDDED_OBJECTS "${USER_DATA_OBJECT}")
    message(STATUS "User data file will be embedded: ${USER_DATA_FILE}")
else()
    message(STATUS "No user data file provided (USER_DATA_FILE not set or file doesn't exist)")
endif()

# Embed modules.dmp if it exists after build
# Note: modules.dmp is created during build, not configuration, so we check for it at build time
set(MODULES_DMP_FILE "${CMAKE_BINARY_DIR}/modules.dmp")
set(MODULES_DMP_OBJECT "${CMAKE_BINARY_DIR}/__modules_dmp.o")

# Create a custom command that will conditionally embed modules.dmp
add_custom_command(
    OUTPUT "${MODULES_DMP_OBJECT}"
    COMMAND ${CMAKE_COMMAND} -E echo "Checking for modules.dmp..."
    COMMAND bash -c "if [ -f ${MODULES_DMP_FILE} ]; then echo 'Embedding modules.dmp'; ${CMAKE_OBJCOPY} --input-target=binary --output-target=elf32-littlearm --binary-architecture=arm --rename-section .data=.embedded.modules_dmp,alloc,load,readonly,data,contents ${MODULES_DMP_FILE} ${MODULES_DMP_OBJECT}; else echo 'No modules.dmp found, creating empty object'; ${CMAKE_OBJCOPY} --input-target=binary --output-target=elf32-littlearm --binary-architecture=arm --rename-section .data=.embedded.modules_dmp,alloc,load,readonly,data,contents /dev/null ${MODULES_DMP_OBJECT}; fi"
    DEPENDS prepare_modules_dmp
    COMMENT "Conditionally embedding modules.dmp if it exists"
    VERBATIM
)

list(APPEND EMBEDDED_OBJECTS "${MODULES_DMP_OBJECT}")
message(STATUS "modules.dmp will be conditionally embedded if created during build")

# ======================================================================
#               dmod-boot application
# ======================================================================
set(MODULE_NAME dmboot)

add_executable(${MODULE_NAME}.elf
    src/main.c
    ${EMBEDDED_OBJECTS}
)

target_compile_definitions(${MODULE_NAME}.elf
    PRIVATE 
        DMBOOT_MCU_SERIES=${DMBOOT_MCU_SERIES}
        DMBOOT_MCU_SERIES_STRING="${DMBOOT_MCU_SERIES}"
        DMBOOT_MCU_NAME=${DMBOOT_MCU_NAME}
        DMBOOT_MCU_NAME_STRING="${DMBOOT_MCU_NAME}"
        DMBOOT_MAX_MOUNT_POINTS=${DMBOOT_MAX_MOUNT_POINTS}
        DMBOOT_MAX_OPEN_FILES=${DMBOOT_MAX_OPEN_FILES}
        DMBOOT_EMULATION_ENABLED=${DMBOOT_EMULATION}
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
#               Target Configuration
# ======================================================================
# Include separate targets configuration script
include(scripts/targets.cmake)

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

# Custom target for monitoring logs via GDB server
add_custom_target(monitor-gdb
    COMMAND ${CMAKE_COMMAND} -E echo "Starting dmlog monitor in GDB mode..."
    COMMAND ${CMAKE_COMMAND} -E echo "Ring buffer address will be read from ${CMAKE_BINARY_DIR}/dmlog_ring_buffer.cmake"
    COMMAND ${CMAKE_COMMAND} 
        -DPROJECT_BINARY_DIR=${CMAKE_BINARY_DIR}
        -DPROJECT_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/scripts/run_monitor_gdb.cmake
    DEPENDS build_dmlog_monitor extract_ring_buffer_config
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Monitoring logs from ${TARGET} via GDB server..."
)