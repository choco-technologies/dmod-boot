# ARMv7-M: the reset handler and the jump; the flags of the core (DMSEL_ARCH_CORE is the name of the core: cortex-m7)
set(DMSEL_ARCH_SOURCES ${CMAKE_CURRENT_LIST_DIR}/startup.c ${CMAKE_CURRENT_LIST_DIR}/jump.c)
set(DMSEL_CPU_FLAGS -mcpu=${DMSEL_ARCH_CORE} -mthumb)
