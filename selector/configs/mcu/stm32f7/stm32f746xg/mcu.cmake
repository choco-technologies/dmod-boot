# STM32F746xG: the flash controller, the watchdog, the memory map
set(DMSEL_MCU_SOURCES ${DMSEL_MCU_DIR}/flash.c ${DMSEL_MCU_DIR}/watchdog.c)
set(DMSEL_MCU_LINKER_SCRIPT ${DMSEL_MCU_DIR}/mcu.ld)
set(DMSEL_MCU_INCLUDE_DIR ${DMSEL_MCU_DIR})
