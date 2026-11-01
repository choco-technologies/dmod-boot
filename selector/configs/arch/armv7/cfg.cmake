# ARMv7-M common to the cores: the reset handler and the jump (the core's flags: <core>/cfg.cmake)
set(DMSEL_ARCH_SOURCES ${DMSEL_CONFIGS_DIR}/arch/armv7/startup.c ${DMSEL_CONFIGS_DIR}/arch/armv7/jump.c)
set(DMSEL_ARCH_LINKER_SCRIPT ${DMSEL_CONFIGS_DIR}/arch/armv7/arch.ld)
