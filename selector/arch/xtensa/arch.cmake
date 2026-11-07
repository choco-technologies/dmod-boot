# Xtensa LX (ESP32-S3): the entry and the jump; the toolchain is the Espressif one (xtensa-esp32s3-elf-, see fw/CMakeLists.txt)
set(DMSEL_ARCH_SOURCES ${CMAKE_CURRENT_LIST_DIR}/startup.c ${CMAKE_CURRENT_LIST_DIR}/jump.c)
set(DMSEL_CPU_FLAGS -mlongcalls)
