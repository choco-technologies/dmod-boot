# The FreeRTOS port for the ESP32-S3 (GCC_XTENSA_ESP32 of FreeRTOS-Kernel) is Espressif's: it takes the headers of the chip and of
# the Xtensa core from ESP-IDF, and a few functions of it (interrupts, log, heap, ...) that this project does not have. The
# headers are used from the ESP-IDF installed on the machine (IDF_PATH), the functions are replaced in shim/. The FreeRTOS of
# ESP-IDF itself (components/freertos) is NOT on the include path: it would shadow the kernel of dmosi-freertos.
# Included after dmosi-freertos has been added (freertos_config exists).
set(DMBOOT_IDF_DIR "$ENV{IDF_PATH}" CACHE PATH "ESP-IDF: the headers of the chip and of the Xtensa core for the FreeRTOS port")
if(NOT EXISTS "${DMBOOT_IDF_DIR}/components/xtensa/esp32s3/include/xtensa/config/core.h")
    message(FATAL_ERROR "ESP-IDF not found (DMBOOT_IDF_DIR='${DMBOOT_IDF_DIR}', set IDF_PATH or -DDMBOOT_IDF_DIR=...): the FreeRTOS port needs its headers")
endif()

add_library(dmboot_idf_headers INTERFACE)
target_include_directories(dmboot_idf_headers INTERFACE
    ${CMAKE_SOURCE_DIR}/src/arch/xtensa/lx7/shim
    ${DMBOOT_IDF_DIR}/components/xtensa/include
    ${DMBOOT_IDF_DIR}/components/xtensa/esp32s3/include
    ${DMBOOT_IDF_DIR}/components/soc/include
    ${DMBOOT_IDF_DIR}/components/soc/esp32s3/include
    ${DMBOOT_IDF_DIR}/components/esp_common/include
    ${DMBOOT_IDF_DIR}/components/esp_hw_support/include
    ${DMBOOT_IDF_DIR}/components/esp_rom/include
    ${DMBOOT_IDF_DIR}/components/esp_rom/include/esp32s3
    ${DMBOOT_IDF_DIR}/components/hal/include
    ${DMBOOT_IDF_DIR}/components/hal/esp32s3/include
    ${DMBOOT_IDF_DIR}/components/esp_system/include
    ${DMBOOT_IDF_DIR}/components/heap/include)
target_link_libraries(freertos_config INTERFACE dmboot_idf_headers)
# (the headers of the vendor are not written for -Werror)
target_compile_options(dmboot_idf_headers INTERFACE -Wno-unused-parameter)

# libxt_hal.a: the functions of the HAL of the Xtensa core that the port calls (xthal_*); the rest of what the port needs from
# ESP-IDF is in shim/ (compiled with it, as an object library: the port and the shim call each other, a static library
# would be in the wrong order for the linker)
target_link_libraries(dmboot_idf_headers INTERFACE ${DMBOOT_IDF_DIR}/components/xtensa/esp32s3/libxt_hal.a)

set(DMBOOT_FREERTOS_PORT_DIR ${CMAKE_SOURCE_DIR}/lib/dmosi-freertos/lib/freertos/portable/ThirdParty/GCC/Xtensa_ESP32)
add_library(dmboot_port_shim OBJECT
    ${CMAKE_SOURCE_DIR}/src/arch/xtensa/lx7/shim/port_shim.c
    ${CMAKE_SOURCE_DIR}/src/arch/xtensa/lx7/shim/panic.S
    # (not in the list of the sources of the port in FreeRTOS-Kernel, and it has the tick and the handler of it)
    ${DMBOOT_FREERTOS_PORT_DIR}/port_systick.c
    # the table of the handlers of the interrupts and of the exceptions, xt_ints_on/off
    ${DMBOOT_IDF_DIR}/components/xtensa/xtensa_intr_asm.S)
target_link_libraries(dmboot_port_shim PRIVATE freertos_kernel freertos_config dmboot_idf_headers)
dmod_set_current_allocator(dmboot_port_shim)

# The handlers of the exceptions of the core (the part of the Fault API of dmosi that is the architecture's): they take over
# the table of xtensa_intr_asm.S, and rewrite the frame of the thread that faulted, so they use the structures of the port
add_library(dmboot_fault OBJECT
    ${CMAKE_SOURCE_DIR}/src/arch/xtensa/lx7/fault.c
    ${CMAKE_SOURCE_DIR}/src/arch/xtensa/lx7/fault_asm.S)
target_link_libraries(dmboot_fault PRIVATE dmod dmosi freertos_kernel freertos_config dmboot_idf_headers)
dmod_set_current_allocator(dmboot_fault)
