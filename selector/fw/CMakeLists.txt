# The selector for the STM32F7 (the code of the first sector of the flash)
#   cmake -S selector/fw -B build-selector-fw && cmake --build build-selector-fw
# Result: dmsel.elf and dmsel.bin (at most 32 kB: the linker script checks)
cmake_minimum_required(VERSION 3.16)
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER arm-none-eabi-gcc)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
project(dmsel_fw C)

set(DMSEL_WATCHDOG_MS 0 CACHE STRING "Watchdog (ms) armed for an image on trial; the firmware has to feed it, 0: none")
set(DMBOOT_DIR "${CMAKE_CURRENT_LIST_DIR}/../..")

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
set(DMOD_CPU_NAME "stm32f746xg")
set(DMOD_ARRAY_SEP ":")
set(DMOD_PATH_SEP "/")
set(DMOD_BUILTIN_COMPRESSION_API OFF)
set(DMOD_BUILD_DIR "${CMAKE_BINARY_DIR}")
set(dmod_VERSION_MAJOR 1)
set(dmod_VERSION_MINOR 0)
configure_file("${DMBOOT_DIR}/lib/dmod/dmod-config.h.in" "${CMAKE_BINARY_DIR}/gen/dmod-config.h")

add_executable(dmsel.elf
    startup.c main.c dmsel_port_f7.c dmod_stubs.c libc_min.c
    ../src/dmsel.c
    ${DMBOOT_DIR}/lib/dmlog/src/dmlog.c)
set_source_files_properties(${DMBOOT_DIR}/lib/dmlog/src/dmlog.c PROPERTIES COMPILE_OPTIONS "-w")
target_include_directories(dmsel.elf PRIVATE . ../include ${DMBOOT_DIR}/lib/dmlog/include ${DMBOOT_DIR}/lib/dmod/inc ${CMAKE_BINARY_DIR}/gen)
target_compile_definitions(dmsel.elf PRIVATE DMOD_EXTERNAL_REGISTRATION DMOD_CURRENT_ALLOCATOR="dmsel" DMSEL_WATCHDOG_MS=${DMSEL_WATCHDOG_MS})
target_compile_options(dmsel.elf PRIVATE -mcpu=cortex-m7 -mthumb -Os -ffunction-sections -fdata-sections -ffreestanding
    -Wall -Wextra -std=gnu11)
target_link_options(dmsel.elf PRIVATE -mcpu=cortex-m7 -mthumb -nostdlib -nostartfiles -Wl,--gc-sections
    -T${CMAKE_CURRENT_LIST_DIR}/dmsel_f7.ld -Wl,-Map=${CMAKE_BINARY_DIR}/dmsel.map -lgcc)
set_target_properties(dmsel.elf PROPERTIES LINK_DEPENDS ${CMAKE_CURRENT_LIST_DIR}/dmsel_f7.ld)
add_custom_command(TARGET dmsel.elf POST_BUILD
    COMMAND arm-none-eabi-objcopy -O binary dmsel.elf dmsel.bin
    COMMAND arm-none-eabi-size dmsel.elf)
