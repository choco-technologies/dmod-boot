# Emulation: the UARTs receive by interrupt.
#
# Renode's STM32F7 USART has no DMA request line, so a UART that receives by
# DMA (dmuart's default) gets nothing there - the console would not read a
# key. dmuart's `rx_dma=0` makes it receive by interrupt, which the model
# serves; the hardware keeps the DMA. Run on the driver configuration the
# modules brought (DMBOOT_CONFIG_DIR/drivers/dmuart/*.ini):
#
#   cmake -DDMUART_CONFIG_DIR=<dir> -P emulation_uart_config.cmake
#
file(GLOB DMUART_INIS "${DMUART_CONFIG_DIR}/*.ini")
foreach(INI ${DMUART_INIS})
    file(READ "${INI}" CONTENT)
    if(CONTENT MATCHES "driver_name=dmuart" AND NOT CONTENT MATCHES "(^|\n)rx_dma=")
        string(REGEX REPLACE "(\n[ \t]*rx_ring_size=[^\n]*)" "\\1\nrx_dma=0" CONTENT "${CONTENT}")
        file(WRITE "${INI}" "${CONTENT}")
    endif()
endforeach()
