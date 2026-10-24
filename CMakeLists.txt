# =====================================================================
#               DMOD Boot CMakeLists.txt
# =====================================================================
cmake_minimum_required(VERSION 3.10)

# ======================================================================
#               Configuration
# ======================================================================
set(TARGET "STM32F746xG" CACHE STRING "Target microcontroller")
set(BOARD "" CACHE STRING "Board name (optional). If set, TARGET is derived from configs/board/<BOARD>/board.cmake")
set(STARTUP_DMP_FILE "" CACHE FILEPATH "Optional startup.dmp file to embed in ROM")
set(USER_DATA_FILE "" CACHE FILEPATH "Optional user_data file to embed in ROM")
set(DMBOOT_CONFIG_DIR "${CMAKE_BINARY_DIR}/cfg" CACHE PATH "Config directory to mount as /cfg/ using dmffs (defaults to build/cfg)")
set(DMBOOT_EVIEWS_DIR "${CMAKE_BINARY_DIR}/eviews" CACHE PATH "Directory with views (.dmv) of the flash modules, one subdirectory per module; embedded as a dmffs image and mounted as /eviews/ (defaults to build/eviews)")
set(DMBOOT_LICENSE_DIR "${CMAKE_BINARY_DIR}/lic" CACHE PATH "Flash module licenses on the host, one subdirectory per module")
option(DMBOOT_EMBED_LICENSES "Embed flash module licenses and mount them at /lic/ (uses flash space)" OFF)
set(DMBOOT_MAIN_MODULE "systemd" CACHE STRING "Name of the main module to start after boot")
set(DMBOOT_MAIN_MODULE_CONFIG "" CACHE STRING "Configuration file for the main module (e.g. board/stm32f746g-disco.ini)")
set(DMBOOT_MAIN_MODULE_ARGS "/cfg/services /cfg/rules" CACHE STRING "Space-separated arguments passed to the main module on startup (argv[0] is always the module name)")
# /configs is /cfg now: a build directory configured before keeps the old defaults in its cache - with them, the
# firmware would mount /cfg and start systemd on /configs.
if(DMBOOT_CONFIG_DIR STREQUAL "${CMAKE_BINARY_DIR}/configs")
    set(DMBOOT_CONFIG_DIR "${CMAKE_BINARY_DIR}/cfg" CACHE PATH "Config directory to mount as /cfg/ using dmffs (defaults to build/cfg)" FORCE)
endif()
if(DMBOOT_MAIN_MODULE_ARGS STREQUAL "/configs/services /configs/rules")
    set(DMBOOT_MAIN_MODULE_ARGS "/cfg/services /cfg/rules" CACHE STRING "Space-separated arguments passed to the main module on startup (argv[0] is always the module name)" FORCE)
endif()
set(DMBOOT_EXTRA_FLASH_DMD_FILES "" CACHE STRING "Additional flash.dmd files to include (semicolon-separated list of absolute paths)")
set(DMBOOT_EXTRA_SDCARD_DMD_FILES "" CACHE STRING "Additional sdcard.dmd files to include (semicolon-separated list of absolute paths)")
set(DMBOOT_EXTRA_EXT_DMD_FILES "" CACHE STRING "Additional ext.dmd files to include (semicolon-separated list of absolute paths)")
set(DMBOOT_MANIFEST_URL "" CACHE STRING "Manifest path/URL to use with dmf-get -m flag for all module downloads")
set(DMBOOT_SHELL "dmell" CACHE STRING "Shell to use by default")
set(DMBOOT_MODULE_TYPE "dmfc" CACHE STRING "Preferred module file type to download (dmfc or dmf). dmf-get falls back to the other type when a package does not provide the preferred one")
set_property(CACHE DMBOOT_MODULE_TYPE PROPERTY STRINGS dmfc dmf)
if(NOT DMBOOT_MODULE_TYPE MATCHES "^(dmf|dmfc)$")
    message(FATAL_ERROR "DMBOOT_MODULE_TYPE must be either 'dmf' or 'dmfc' (got '${DMBOOT_MODULE_TYPE}')")
endif()
option(DMBOOT_EMULATION "Enable Renode emulation mode" OFF)
option(DMBOOT_RENODE_WAIT_FOR_GDB "Keep the Renode machine paused until a GDB client continues it" OFF)

# Convert relative manifest path to absolute so it remains valid when the
# working directory changes during the build (e.g. dmf-get is invoked from a
# different directory than where cmake was originally run).
if(DMBOOT_MANIFEST_URL AND NOT DMBOOT_MANIFEST_URL MATCHES "://")
    get_filename_component(DMBOOT_MANIFEST_URL "${DMBOOT_MANIFEST_URL}" ABSOLUTE BASE_DIR "${CMAKE_BINARY_DIR}")
    message(STATUS "Resolved manifest path to absolute: ${DMBOOT_MANIFEST_URL}")
endif()

# ======================================================================
#               Early DMOD Configuration (before project())
# ======================================================================
set(DMOD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib/dmod")
include(configs/dmod-cfg.cmake)
include(configs/dmvfs-cfg.cmake)

# If BOARD is specified, read TARGET from board.cmake
if(BOARD)
    include(configs/board/${BOARD}/board.cmake)
endif()

include(configs/mcu/${TARGET}.cmake)

# The heaps' names - dmheap tags: kinds of memory, separated by commas, that
# drivers find a heap by (dmheap_get_context_by_name("dma")) and modules ask
# for (Dmod_MallocTagged("fast", ...)). After the MCU configuration, which
# says what its memories are.
set(DMBOOT_DMA_HEAP_TAGS "dma" CACHE STRING "Tags of the DMA heap (linker region dma): dma, and e.g. fast where it is fast internal RAM")
set(DMBOOT_MAIN_HEAP_TAGS "main" CACHE STRING "Tags of the main heap (linker region ram)")

# Splash logo - after the board configuration, which picks the asset
set(DMBOOT_SPLASH_LOGO "" CACHE STRING "Splash logo the display driver shows at start: name of an asset in assets/splash/ (e.g. dmodos_logo_128) or a path to a .dmvi file; empty: no logo")
set(DMBOOT_SPLASH_LOGO_PATH "/eviews/splash_logo.dmvir" CACHE STRING "Path of the splash logo (.dmvir) on the target, passed to the display driver in the SPLASH_LOGO environment variable; empty: not set")

# The device secret: the root of what the system keeps encrypted at rest (dmsecrets). dmod-boot hands
# it to dmdevfs in the mount string ("/cfg/drivers,<secret>"); dmdevfs serves it as the read-only
# node /dev/devkey. It is whatever is given here (1..64 bytes of text), else the content of the
# DMBOOT_DEVICE_SECRET_FILE, which is made with a random secret when it is missing (and keeps the
# secret the same across rebuilds and fresh build directories: a firmware update does not change it).
# Flashing a firmware built with another secret makes the vaults of the old one unreadable - they are
# made again. Empty both: no secret, no /dev/devkey.
set(DMBOOT_DEVICE_SECRET "" CACHE STRING "Device secret (1..64 bytes of text; no control characters). Empty: read from / generated into DMBOOT_DEVICE_SECRET_FILE")
set(DMBOOT_DEVICE_SECRET_FILE "${CMAKE_CURRENT_SOURCE_DIR}/device.secret" CACHE FILEPATH "File holding the device secret (made with a random one when missing); empty (with an empty DMBOOT_DEVICE_SECRET): no device secret")

# Where the vaults of dmsecrets are (the DMSECRETS_PATH environment variable, set at boot): a file on a
# filesystem that is there when the service that needs it runs, e.g. on the SD card (/mnt/<label or node>/
# secrets.vault). Empty: not set - every library then needs a path of its own (DMSECRETS_<DOMAIN>_PATH).
set(DMBOOT_DMSECRETS_PATH "" CACHE STRING "Path of the default dmsecrets vault (DMSECRETS_PATH at boot); empty: not set")

# Include toolchain configuration before project() to set compilers
# Check for a local override first, then fall back to the dmod library
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/configs/arch/${DMBOOT_ARCH}/${DMBOOT_ARCH_FAMILY}/tools-cfg.cmake")
    include("${CMAKE_CURRENT_SOURCE_DIR}/configs/arch/${DMBOOT_ARCH}/${DMBOOT_ARCH_FAMILY}/tools-cfg.cmake")
else()
    include(${DMOD_DIR}/configs/arch/${DMBOOT_ARCH}/${DMBOOT_ARCH_FAMILY}/tools-cfg.cmake)
endif()

# ======================================================================
#               DMOD Boot Project Configuration
# ======================================================================
project(dmboot
    VERSION 1.0
    DESCRIPTION "DMOD Bootloader"
    LANGUAGES C CXX ASM)

# ======================================================================
#               For VS Code
# ======================================================================
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

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

# Splash logo, built into the embedded views filesystem (sets DMBOOT_SPLASH_LOGO_FILE)
include(scripts/splash.cmake)

# Embed configuration, views and license filesystems
include(scripts/romfs.cmake)
if(CONFIG_FS_OBJECT)
    list(APPEND EMBEDDED_OBJECTS "${CONFIG_FS_OBJECT}")
endif()
if(EVIEWS_FS_OBJECT)
    list(APPEND EMBEDDED_OBJECTS "${EVIEWS_FS_OBJECT}")
endif()
if(LICENSE_FS_OBJECT)
    list(APPEND EMBEDDED_OBJECTS "${LICENSE_FS_OBJECT}")
endif()

# Embed modules.dmp if it exists after build
# Note: modules.dmp is created during build, not configuration, so we check for it at build time
set(MODULES_DMP_FILE "${CMAKE_BINARY_DIR}/modules.dmp")
set(MODULES_DMP_OBJECT "${CMAKE_BINARY_DIR}/__modules_dmp.o")

# Create a custom command that will conditionally embed modules.dmp
add_custom_command(
    OUTPUT "${MODULES_DMP_OBJECT}"
    COMMAND ${CMAKE_COMMAND} -E echo "Checking for modules.dmp..."
    COMMAND bash -c "if [ -f ${MODULES_DMP_FILE} ]; then echo 'Embedding modules.dmp'; ${CMAKE_OBJCOPY} --input-target=binary --output-target=${DMBOOT_OBJCOPY_OUTPUT_FORMAT} --binary-architecture=${DMBOOT_OBJCOPY_BINARY_ARCH} --rename-section .data=.embedded.modules_dmp,alloc,load,readonly,data,contents ${MODULES_DMP_FILE} ${MODULES_DMP_OBJECT}; else echo 'No modules.dmp found, creating empty object'; ${CMAKE_OBJCOPY} --input-target=binary --output-target=${DMBOOT_OBJCOPY_OUTPUT_FORMAT} --binary-architecture=${DMBOOT_OBJCOPY_BINARY_ARCH} --rename-section .data=.embedded.modules_dmp,alloc,load,readonly,data,contents /dev/null ${MODULES_DMP_OBJECT}; fi"
    DEPENDS "${MODULES_DMP_FILE}" prepare_modules_dmp
    COMMENT "Conditionally embedding modules.dmp if it exists"
    VERBATIM
)

list(APPEND EMBEDDED_OBJECTS "${MODULES_DMP_OBJECT}")
message(STATUS "modules.dmp will be conditionally embedded if created during build")

# ======================================================================
#               Fetch RTOS
# ======================================================================
# Currently we support only FreeRTOS, but in the future this 
# part should be dependent on the selected RTOS (if more are supported)
set(DMOSI_ARCH        ${DMBOOT_ARCH} CACHE STRING "Architecture for dmosi-freertos configuration")
set(DMOSI_ARCH_FAMILY ${DMBOOT_ARCH_FAMILY} CACHE STRING "Architecture family for dmosi-freertos configuration")

add_subdirectory(lib/dmosi-freertos)

# ======================================================================
#               dmod-boot application
# ======================================================================
set(MODULE_NAME dmboot)

# ----------------------------------------------------------------------
#               The device secret
# ----------------------------------------------------------------------
set(DMBOOT_DEVICE_SECRET_VALUE "${DMBOOT_DEVICE_SECRET}")
if("${DMBOOT_DEVICE_SECRET_VALUE}" STREQUAL "" AND NOT "${DMBOOT_DEVICE_SECRET_FILE}" STREQUAL "")
    if(NOT EXISTS "${DMBOOT_DEVICE_SECRET_FILE}")
        # 32 random bytes as 64 hex characters (the longest secret dmdevfs takes)
        file(READ /dev/urandom DMBOOT_DEVICE_SECRET_RANDOM LIMIT 32 HEX)
        string(LENGTH "${DMBOOT_DEVICE_SECRET_RANDOM}" DMBOOT_DEVICE_SECRET_RANDOM_LENGTH)
        if(NOT DMBOOT_DEVICE_SECRET_RANDOM_LENGTH EQUAL 64)
            message(FATAL_ERROR "Cannot read random bytes for the device secret: give DMBOOT_DEVICE_SECRET")
        endif()
        file(WRITE "${DMBOOT_DEVICE_SECRET_FILE}" "${DMBOOT_DEVICE_SECRET_RANDOM}\n")
        message(STATUS "Device secret: made a random one in ${DMBOOT_DEVICE_SECRET_FILE} (keep it: a firmware built with another one cannot read the vaults of this one)")
    endif()
    file(READ "${DMBOOT_DEVICE_SECRET_FILE}" DMBOOT_DEVICE_SECRET_VALUE)
    string(STRIP "${DMBOOT_DEVICE_SECRET_VALUE}" DMBOOT_DEVICE_SECRET_VALUE)
    message(STATUS "Device secret: from ${DMBOOT_DEVICE_SECRET_FILE}")
endif()

if(NOT "${DMBOOT_DEVICE_SECRET_VALUE}" STREQUAL "")
    string(LENGTH "${DMBOOT_DEVICE_SECRET_VALUE}" DMBOOT_DEVICE_SECRET_LENGTH)
    if(DMBOOT_DEVICE_SECRET_LENGTH GREATER 64)
        message(FATAL_ERROR "The device secret is ${DMBOOT_DEVICE_SECRET_LENGTH} bytes, dmdevfs takes at most 64")
    endif()
    if("${DMBOOT_DEVICE_SECRET_VALUE}" MATCHES "[^ -~]")
        message(FATAL_ERROR "The device secret may only have printable ASCII characters")
    endif()
    # as the body of a C string literal
    string(REPLACE "\\" "\\\\" DMBOOT_DEVICE_SECRET_C "${DMBOOT_DEVICE_SECRET_VALUE}")
    string(REPLACE "\"" "\\\"" DMBOOT_DEVICE_SECRET_C "${DMBOOT_DEVICE_SECRET_C}")
    set(DMBOOT_DEVICE_SECRET_HEADER "${CMAKE_BINARY_DIR}/device_secret.h")
    file(WRITE "${DMBOOT_DEVICE_SECRET_HEADER}.tmp"
        "/* Made by CMake from DMBOOT_DEVICE_SECRET / DMBOOT_DEVICE_SECRET_FILE - not for the repository. */\n"
        "#define DMBOOT_DEVICE_SECRET_STRING \"${DMBOOT_DEVICE_SECRET_C}\"\n")
    # touched only when it changes: a rebuild does not recompile for nothing
    execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different "${DMBOOT_DEVICE_SECRET_HEADER}.tmp" "${DMBOOT_DEVICE_SECRET_HEADER}")
    file(REMOVE "${DMBOOT_DEVICE_SECRET_HEADER}.tmp")
else()
    set(DMBOOT_DEVICE_SECRET_HEADER "")
endif()

add_executable(${MODULE_NAME}.elf
    src/main.c
    ${EMBEDDED_OBJECTS}
)

if(NOT "${DMBOOT_DEVICE_SECRET_HEADER}" STREQUAL "")
    target_compile_definitions(${MODULE_NAME}.elf PRIVATE DMBOOT_HAS_DEVICE_SECRET=1)
    target_include_directories(${MODULE_NAME}.elf PRIVATE ${CMAKE_BINARY_DIR})
endif()

dmod_set_current_allocator(${MODULE_NAME}.elf)

target_compile_definitions(${MODULE_NAME}.elf
    PRIVATE 
        DMBOOT_MCU_SERIES=${DMBOOT_MCU_SERIES}
        DMBOOT_MCU_SERIES_STRING="${DMBOOT_MCU_SERIES}"
        DMBOOT_MCU_NAME=${DMBOOT_MCU_NAME}
        DMBOOT_MCU_NAME_STRING="${DMBOOT_MCU_NAME}"
        DMBOOT_MAX_MOUNT_POINTS=${DMBOOT_MAX_MOUNT_POINTS}
        DMBOOT_MAX_OPEN_FILES=${DMBOOT_MAX_OPEN_FILES}
        DMBOOT_IRQ_COUNT=${DMBOOT_IRQ_COUNT}
        DMBOOT_IRQ_MAX_HANDLERS_PER_IRQ=${DMBOOT_IRQ_MAX_HANDLERS_PER_IRQ}
        DMBOOT_EMULATION_ENABLED=${DMBOOT_EMULATION}
        DMBOOT_SHELL_STRING="${DMBOOT_SHELL}"
        DMBOOT_MAIN_MODULE_ARGS_STRING="${DMBOOT_MAIN_MODULE_ARGS}"
        DMBOOT_SPLASH_LOGO_PATH_STRING="${DMBOOT_SPLASH_LOGO_PATH}"
        DMBOOT_DMSECRETS_PATH_STRING="${DMBOOT_DMSECRETS_PATH}"
        DMBOOT_DMA_HEAP_TAGS_STRING="${DMBOOT_DMA_HEAP_TAGS}"
        DMBOOT_MAIN_HEAP_TAGS_STRING="${DMBOOT_MAIN_HEAP_TAGS}"
)

target_link_options(${MODULE_NAME}.elf
    PRIVATE 
        -L${DMOD_DIR}/scripts
        -T${CMAKE_CURRENT_SOURCE_DIR}/configs/arch/${DMBOOT_ARCH}/arch.ld
        -T${CMAKE_CURRENT_SOURCE_DIR}/configs/mcu/${DMBOOT_MCU_SERIES}/${DMBOOT_MCU_NAME}/mcu.ld
        -T${CMAKE_CURRENT_SOURCE_DIR}/linker/common.ld
        -Wl,-Map=${MODULE_NAME}.map
)

target_link_libraries(${MODULE_NAME}.elf
    PRIVATE 
        dmod
        dmlog
        dmheap
        dmlist
        dmvfs
        dmenv
        dmboot_inc
        dmboot_startup
        dmboot_arch
        dmosi_freertos
)

if(TARGET dmboot_power)
    target_link_libraries(${MODULE_NAME}.elf PRIVATE dmboot_power)
endif()

# Core-specific code that replaces weak defaults (e.g. the Cortex-M7 caches)
if(TARGET dmboot_cpu)
    target_link_libraries(${MODULE_NAME}.elf PRIVATE dmboot_cpu)
endif()

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