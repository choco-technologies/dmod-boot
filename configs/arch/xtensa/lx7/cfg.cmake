# ======================================================================
#               DMOD Tools Configuration – Xtensa LX7
# ======================================================================
set(DMOD_TOOLS_NAME "arch/xtensa/lx7" CACHE STRING "Name of the tools configuration")

# ======================================================================
#               FreeRTOS port (dmosi-freertos maps only the family "esp32")
# ======================================================================
set(FREERTOS_PORT "GCC_XTENSA_ESP32" CACHE STRING "FreeRTOS port")
set(FREERTOS_ARCH_CONFIG_SUBDIR "xtensa_esp32" CACHE STRING "Architecture configuration directory of dmosi-freertos")
