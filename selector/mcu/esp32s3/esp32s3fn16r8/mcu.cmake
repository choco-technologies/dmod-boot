# ESP32-S3 (FN16R8): the flash through the cache and the ROM's driver, the USB-Serial/JTAG console, the watchdogs
set(DMSEL_MCU_SOURCES ${CMAKE_CURRENT_LIST_DIR}/flash.c ${CMAKE_CURRENT_LIST_DIR}/console.c ${CMAKE_CURRENT_LIST_DIR}/system.c
    ${CMAKE_CURRENT_LIST_DIR}/image.c)
set(DMSEL_MCU_INCLUDE_DIR ${CMAKE_CURRENT_LIST_DIR})

# The linker scripts: the selector runs from the RAM, so the sections are those of ram.ld, not of common.ld
set(DMSEL_LINKER_SCRIPTS
    ${DMBOOT_DIR}/configs/mcu/${DMSEL_MCU_SERIES}/${DMSEL_MCU}/selector.ld
    ${DMBOOT_DIR}/configs/arch/${DMSEL_ARCH}/selector.ld
    ${CMAKE_CURRENT_LIST_DIR}/../../../linker/ram.ld)

# What the ROM boots is an image of ESP-IDF's format (the header, the segments with their load addresses, the checksum, the
# digest) at the offset 0 of the flash: esptool makes it from the ELF. The flash is 16 MB, DIO at 40 MHz needs no tuning of
# the flash timing (that the ROM does not do for a 2nd stage that is not ESP-IDF's).
#   -DDMSEL_ESPTOOL=<path>   esptool (pip install esptool); by default the one in the PATH
if(NOT DMSEL_ESPTOOL)
    find_program(DMSEL_ESPTOOL NAMES esptool esptool.py)
endif()
if(NOT DMSEL_ESPTOOL)
    message(FATAL_ERROR "esptool not found (pip install esptool, or -DDMSEL_ESPTOOL=<path>)")
endif()
set(DMSEL_IMAGE_COMMAND ${DMSEL_ESPTOOL} --chip esp32s3 elf2image --flash-mode dio --flash-freq 40m --flash-size 16MB
    -o dmsel.bin dmsel.elf)
