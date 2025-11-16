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
set(DMBOOT_ROMFS_DIR "" CACHE PATH "Optional directory to create ROM filesystem from")
set(DMBOOT_MAKE_DMFFS_MODULE "" CACHE FILEPATH "Path to make_dmffs.dmf module (auto-detected if not specified)")
set(DMBOOT_DMOD_LOADER "" CACHE FILEPATH "Path to dmod_loader executable (auto-detected if not specified)")
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

# ======================================================================
#               Modules Build and Packaging
# ======================================================================
# Build modules in a separate build directory with DMOD_MODULE mode
# Treat modules/ as a separate CMake project
set(MODULES_BUILD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/modules/build")
set(MODULES_DMP_FILE "${MODULES_BUILD_DIR}/modules.dmp")

# Custom target to configure and build modules as a separate project
add_custom_command(
    OUTPUT ${MODULES_DMP_FILE}
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${MODULES_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${MODULES_BUILD_DIR}
    COMMAND ${CMAKE_COMMAND} -E chdir ${MODULES_BUILD_DIR}
        ${CMAKE_COMMAND} 
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        -DDMOD_TOOLS_NAME=arch/x86_64
        ${CMAKE_CURRENT_SOURCE_DIR}/modules
    COMMAND ${CMAKE_COMMAND} --build ${MODULES_BUILD_DIR} --target package_modules
    COMMENT "Building and packaging DMOD modules..."
    VERBATIM
)

add_custom_target(build_modules
    DEPENDS ${MODULES_DMP_FILE}
)

# ======================================================================
#               ROMFS Generation (if DMBOOT_ROMFS_DIR is set)
# ======================================================================
if(DMBOOT_ROMFS_DIR AND EXISTS "${DMBOOT_ROMFS_DIR}")
    set(ROMFS_BIN_FILE "${CMAKE_BINARY_DIR}/romfs.bin")
    
    # Auto-detect or validate dmod_loader
    if(NOT DMBOOT_DMOD_LOADER)
        find_program(DMBOOT_DMOD_LOADER dmod_loader)
        if(NOT DMBOOT_DMOD_LOADER)
            message(STATUS "dmod_loader not found in PATH")
            # Check if we're likely in Docker environment
            if(EXISTS "/tools/dmf/make_dmffs.dmf")
                message(STATUS "Docker environment detected, dmod_loader should be available at build time")
                set(DMBOOT_DMOD_LOADER "dmod_loader")
            else()
                message(STATUS "Will build dmod_loader from dmod repository")
                set(DMOD_TOOLS_BUILD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib/dmod/build_tools")
                set(DMBOOT_DMOD_LOADER "${DMOD_TOOLS_BUILD_DIR}/bin/tools/dmod_loader")
                
                # Build dmod_loader for x86
                add_custom_command(
                    OUTPUT ${DMBOOT_DMOD_LOADER}
                    COMMAND ${CMAKE_COMMAND} -E make_directory ${DMOD_TOOLS_BUILD_DIR}
                    COMMAND ${CMAKE_COMMAND} -E chdir ${DMOD_TOOLS_BUILD_DIR}
                        ${CMAKE_COMMAND} 
                        -DDMOD_MODE=DMOD_SYSTEM
                        -DDMOD_BUILD_TOOLS=ON
                        ${CMAKE_CURRENT_SOURCE_DIR}/lib/dmod
                    COMMAND ${CMAKE_COMMAND} --build ${DMOD_TOOLS_BUILD_DIR}
                    COMMENT "Building dmod_loader tool..."
                    VERBATIM
                )
                
                add_custom_target(build_dmod_loader
                    DEPENDS ${DMBOOT_DMOD_LOADER}
                )
            endif()
        endif()
    endif()
    
    # Auto-detect or validate make_dmffs module
    if(NOT DMBOOT_MAKE_DMFFS_MODULE)
        # Try common locations
        set(MAKE_DMFFS_SEARCH_PATHS
            "/tools/dmf/make_dmffs.dmf"
            "${CMAKE_CURRENT_SOURCE_DIR}/lib/dmod/build_tools/dmf/make_dmffs.dmf"
            "${MODULES_BUILD_DIR}/dmf/make_dmffs.dmf"
        )
        
        foreach(SEARCH_PATH ${MAKE_DMFFS_SEARCH_PATHS})
            if(EXISTS ${SEARCH_PATH})
                set(DMBOOT_MAKE_DMFFS_MODULE ${SEARCH_PATH})
                break()
            endif()
        endforeach()
        
        if(NOT DMBOOT_MAKE_DMFFS_MODULE)
            message(STATUS "make_dmffs.dmf not found, will use module from modules build")
            set(DMBOOT_MAKE_DMFFS_MODULE "${MODULES_BUILD_DIR}/dmf/make_dmffs.dmf")
            # Depend on modules build to ensure make_dmffs is available
            set(ROMFS_EXTRA_DEPENDS build_modules)
        endif()
    endif()
    
    message(STATUS "Using dmod_loader: ${DMBOOT_DMOD_LOADER}")
    message(STATUS "Using make_dmffs module: ${DMBOOT_MAKE_DMFFS_MODULE}")
    
    # Set up dependencies
    set(ROMFS_DEPENDS ${DMBOOT_ROMFS_DIR})
    if(TARGET build_dmod_loader)
        list(APPEND ROMFS_DEPENDS ${DMBOOT_DMOD_LOADER})
    endif()
    if(ROMFS_EXTRA_DEPENDS)
        list(APPEND ROMFS_DEPENDS ${ROMFS_EXTRA_DEPENDS})
    endif()
    
    add_custom_command(
        OUTPUT ${ROMFS_BIN_FILE}
        COMMAND ${DMBOOT_DMOD_LOADER} ${DMBOOT_MAKE_DMFFS_MODULE} --args ${DMBOOT_ROMFS_DIR} ${ROMFS_BIN_FILE}
        DEPENDS ${ROMFS_DEPENDS}
        COMMENT "Generating ROMFS from ${DMBOOT_ROMFS_DIR}..."
        VERBATIM
    )
    
    add_custom_target(build_romfs
        DEPENDS ${ROMFS_BIN_FILE}
    )
    
    message(STATUS "ROMFS will be generated from: ${DMBOOT_ROMFS_DIR}")
else()
    message(STATUS "No ROMFS directory provided (DMBOOT_ROMFS_DIR not set or directory doesn't exist)")
endif()

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

# Embed modules.dmp (always built)
embed_binary_file(
    INPUT_FILE "${MODULES_DMP_FILE}"
    SECTION_NAME ".embedded.modules_dmp"
    SYMBOL_PREFIX "__modules_dmp"
    ALLOW_MISSING
)
set(MODULES_DMP_OBJECT "${CMAKE_BINARY_DIR}/__modules_dmp.o")
list(APPEND EMBEDDED_OBJECTS "${MODULES_DMP_OBJECT}")
message(STATUS "Modules DMP file will be embedded: ${MODULES_DMP_FILE}")

# Embed romfs.bin if DMBOOT_ROMFS_DIR is set
if(DMBOOT_ROMFS_DIR AND EXISTS "${DMBOOT_ROMFS_DIR}")
    embed_binary_file(
        INPUT_FILE "${ROMFS_BIN_FILE}"
        SECTION_NAME ".embedded.romfs"
        SYMBOL_PREFIX "__romfs"
        ALLOW_MISSING
    )
    set(ROMFS_OBJECT "${CMAKE_BINARY_DIR}/__romfs.o")
    list(APPEND EMBEDDED_OBJECTS "${ROMFS_OBJECT}")
    message(STATUS "ROMFS binary will be embedded: ${ROMFS_BIN_FILE}")
else()
    message(STATUS "No ROMFS binary to embed")
endif()

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