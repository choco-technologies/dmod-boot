# The selector (the code of the first sector of the flash)
#   cmake -S selector/fw -B build-selector-fw [-DDMSEL_BOARD=stm32f746g-disco] && cmake --build build-selector-fw
# Result: dmsel.elf and dmsel.bin (at most the sectors before the store: the linker script checks)
#
# The layout of the flash is the board's (configs/board/<board>/board.cmake of dmboot: DMBOOT_BANK_*, DMBOOT_SELECTOR_*),
# the memory map and the entry are in configs/mcu/.../selector.ld and configs/arch/.../selector.ld. The code that depends
# on the platform is in selector/arch/<arch>, selector/mcu/<series>/<mcu>; dmboot passes the names of its target
# (DMSEL_ARCH ...), the defaults are those of the default board.
cmake_minimum_required(VERSION 3.16)
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER arm-none-eabi-gcc)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
project(dmsel_fw C)

set(DMSEL_WATCHDOG_MS 0 CACHE STRING "Watchdog (ms) armed for an image on trial; the firmware has to feed it, 0: none")
set(DMSEL_MAX_TRIES 3 CACHE STRING "Starts of an image on trial that does not confirm, before it is dropped")
set(DMBOOT_DIR "${CMAKE_CURRENT_LIST_DIR}/../..")

set(DMSEL_BOARD "stm32f746g-disco" CACHE STRING "Board the selector is built for (configs/board of dmboot)")
set(DMSEL_ARCH "armv7" CACHE STRING "Architecture (selector/arch, configs/arch)")
set(DMSEL_ARCH_CORE "cortex-m7" CACHE STRING "Core")
set(DMSEL_MCU_SERIES "stm32f7" CACHE STRING "Series of the microcontroller (selector/mcu)")
set(DMSEL_MCU "stm32f746xg" CACHE STRING "Microcontroller")

set(DMSEL_BOARD_FILE "${DMBOOT_DIR}/configs/board/${DMSEL_BOARD}/board.cmake")
if(NOT EXISTS "${DMSEL_BOARD_FILE}")
    message(FATAL_ERROR "dmboot has no board '${DMSEL_BOARD}' (configs/board)")
endif()
include("${DMSEL_BOARD_FILE}")
include("${CMAKE_CURRENT_LIST_DIR}/../arch/${DMSEL_ARCH}/arch.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/../mcu/${DMSEL_MCU_SERIES}/${DMSEL_MCU}/mcu.cmake")

# The layout: offsets from the start of the flash (the selector's origin)
math(EXPR DMSEL_STORE_OFFSET "${DMBOOT_SELECTOR_STORE} - ${DMBOOT_SELECTOR_ORIGIN}" OUTPUT_FORMAT HEXADECIMAL)
math(EXPR DMSEL_STORE_SIZE "${DMBOOT_SELECTOR_STORE_SIZE}" OUTPUT_FORMAT HEXADECIMAL)
math(EXPR DMSEL_ROM_LENGTH "${DMBOOT_SELECTOR_STORE} - ${DMBOOT_SELECTOR_ORIGIN}" OUTPUT_FORMAT HEXADECIMAL)
set(DMSEL_BANK_COUNT 0)
set(DMSEL_BANKS_INIT "")
foreach(letter IN ITEMS A B C D)
    if(DEFINED DMBOOT_BANK_${letter}_ORIGIN)
        math(EXPR offset "${DMBOOT_BANK_${letter}_ORIGIN} - ${DMBOOT_SELECTOR_ORIGIN}" OUTPUT_FORMAT HEXADECIMAL)
        string(APPEND DMSEL_BANKS_INIT "{ ${offset}u, ${DMBOOT_BANK_${letter}_SIZE}u }, ")
        math(EXPR DMSEL_BANK_COUNT "${DMSEL_BANK_COUNT} + 1")
    endif()
endforeach()
configure_file("${CMAKE_CURRENT_LIST_DIR}/dmsel_layout.h.in" "${CMAKE_BINARY_DIR}/gen/dmsel_layout.h" @ONLY)

# dmlog.c wants the configuration header of dmod: a bare-metal one, as the firmware has it
set(DMOD_VERSION_STRING "1.0")
foreach(opt STDLIB GETENV ENVIRON STDIO DIRENT ASSERT PTHREAD MMAN ALIGNED_ALLOC ALIGNED_MALLOC_MOCK REALLOC TERMIOS TIME DMCOMP_ENCODER)
    set(DMOD_USE_${opt} OFF)
endforeach()
set(DMOD_USE_FASTLZ OFF)
set(DMOD_USE_DMCOMP OFF)
set(DMOD_IMPLEMENT_PRINTF OFF)
set(DMOD_IMPLEMENT_SCANF OFF)
set(DMOD_MAX_MODULES 1)
set(DMOD_MAX_REQUIRED_MODULES 1)
set(DMOD_VFPRINTF_STACK_BUFFER_SIZE 100)
set(DMOD_MODE "DMOD_SYSTEM")
set(DMOD_SYSTEM ON)
set(DMOD_MODULE OFF)
set(DMOD_SYSTEM_VERSION_MAJOR 0)
set(DMOD_SYSTEM_VERSION_MINOR 1)
set(DMOD_REPO_DIR "/")
set(DMOD_REPO_PATHS "/")
set(DMOD_CPU_NAME "${DMSEL_MCU}")
set(DMOD_ARRAY_SEP ":")
set(DMOD_PATH_SEP "/")
set(DMOD_BUILTIN_COMPRESSION_API OFF)
set(DMOD_BUILD_DIR "${CMAKE_BINARY_DIR}")
set(dmod_VERSION_MAJOR 1)
set(dmod_VERSION_MINOR 0)
configure_file("${DMBOOT_DIR}/lib/dmod/dmod-config.h.in" "${CMAKE_BINARY_DIR}/gen/dmod-config.h")

add_executable(dmsel.elf
    main.c dmod_stubs.c libc_min.c
    ${DMSEL_ARCH_SOURCES} ${DMSEL_MCU_SOURCES}
    ../src/dmsel.c
    ${DMBOOT_DIR}/lib/dmlog/src/dmlog.c)
set_source_files_properties(${DMBOOT_DIR}/lib/dmlog/src/dmlog.c PROPERTIES COMPILE_OPTIONS "-w")
target_include_directories(dmsel.elf PRIVATE ../include ${DMSEL_MCU_INCLUDE_DIR}
    ${DMBOOT_DIR}/lib/dmlog/include ${DMBOOT_DIR}/lib/dmod/inc ${CMAKE_BINARY_DIR}/gen)
target_compile_definitions(dmsel.elf PRIVATE DMOD_EXTERNAL_REGISTRATION DMOD_CURRENT_ALLOCATOR="dmsel")
target_compile_options(dmsel.elf PRIVATE ${DMSEL_CPU_FLAGS} -Os -ffunction-sections -fdata-sections -ffreestanding
    -Wall -Wextra -std=gnu11)
# (the order matters: the memory map first, the entry and the stack of the core use it, the sections last)
set(DMSEL_LINKER_SCRIPTS
    ${DMBOOT_DIR}/configs/mcu/${DMSEL_MCU_SERIES}/${DMSEL_MCU}/selector.ld
    ${DMBOOT_DIR}/configs/arch/${DMSEL_ARCH}/selector.ld
    ${CMAKE_CURRENT_LIST_DIR}/../linker/common.ld)
set(DMSEL_LINK_SCRIPT_OPTIONS)
foreach(script IN LISTS DMSEL_LINKER_SCRIPTS)
    list(APPEND DMSEL_LINK_SCRIPT_OPTIONS -T${script})
endforeach()
target_link_options(dmsel.elf PRIVATE ${DMSEL_CPU_FLAGS} -nostdlib -nostartfiles -Wl,--gc-sections
    -Wl,--defsym=DMSEL_ROM_ORIGIN=${DMBOOT_SELECTOR_ORIGIN} -Wl,--defsym=DMSEL_ROM_LENGTH=${DMSEL_ROM_LENGTH}
    ${DMSEL_LINK_SCRIPT_OPTIONS} -Wl,-Map=${CMAKE_BINARY_DIR}/dmsel.map -lgcc)
set_target_properties(dmsel.elf PROPERTIES LINK_DEPENDS "${DMSEL_LINKER_SCRIPTS}")
add_custom_command(TARGET dmsel.elf POST_BUILD
    COMMAND arm-none-eabi-objcopy -O binary dmsel.elf dmsel.bin
    COMMAND arm-none-eabi-size dmsel.elf)
