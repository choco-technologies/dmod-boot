# ======================================================================
#               CMake Targets Configuration
# ======================================================================
# This file defines all custom targets for the dmod-boot project
# including install-firmware, connect, debug, monitor, and monitor-gdb

# ======================================================================
#               GDB Init Script Configuration
# ======================================================================
# Generate GDB init script from template with target-specific variables
# Use emulation-specific template in emulation mode, otherwise use hardware template
if(DMBOOT_EMULATION)
    set(GDB_INIT_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/configs/gdb/gdb_init_renode.gdb.in")
else()
    set(GDB_INIT_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/configs/gdb/gdb_init.gdb.in")
endif()

configure_file(
    ${GDB_INIT_TEMPLATE}
    ${CMAKE_BINARY_DIR}/gdb_init.gdb
    @ONLY
)

# Configure Renode script path
# With DMBOOT_RENODE_WAIT_FOR_GDB the machine is not started by the script, the
# first GDB 'continue' starts it - so nothing runs before a debugger attaches
if(DMBOOT_RENODE_WAIT_FOR_GDB)
    set(DMBOOT_RENODE_START "")
else()
    set(DMBOOT_RENODE_START "start")
endif()
# Expose the board's console UART (if it names one) as a raw TCP terminal, so
# the shell running on it can be driven from outside the emulator
set(DMBOOT_RENODE_UART_PORT "3456" CACHE STRING "TCP port of the Renode terminal attached to the console UART")
if(DMBOOT_RENODE_CONSOLE_UART AND DMBOOT_RENODE_UART_PORT)
    set(DMBOOT_RENODE_UART_TERMINAL
        "emulation CreateServerSocketTerminal ${DMBOOT_RENODE_UART_PORT} \"console_uart\" false\nconnector Connect ${DMBOOT_RENODE_CONSOLE_UART} console_uart")
else()
    set(DMBOOT_RENODE_UART_TERMINAL "")
endif()
# Connect the board's Ethernet (if it names one) to a TAP interface on the
# host through a Renode switch, so the host can talk to the board over IP.
# Opening a TAP needs root (CAP_NET_ADMIN) and /dev/net/tun, so it is opt-in.
set(DMBOOT_RENODE_TAP "" CACHE STRING "Host TAP interface the board's Ethernet is connected to in emulation mode (needs root and /dev/net/tun); empty: not connected")
if(DMBOOT_RENODE_ETHERNET AND DMBOOT_RENODE_TAP)
    set(DMBOOT_RENODE_NETWORK
        "emulation CreateSwitch \"switch\"\nconnector Connect ${DMBOOT_RENODE_ETHERNET} switch\nemulation CreateTap \"${DMBOOT_RENODE_TAP}\" \"tap\"\nconnector Connect host.tap switch")
else()
    set(DMBOOT_RENODE_NETWORK "")
endif()
set(RENODE_SCRIPT_PATH "${CMAKE_BINARY_DIR}/renode.resc")
configure_file(
    ${CMAKE_SOURCE_DIR}/configs/renode/renode.resc.in
    ${RENODE_SCRIPT_PATH}
    @ONLY
)

# ======================================================================
#               Firmware Installation and Connection Targets
# ======================================================================

# Configure install-firmware command based on mode
if(DMBOOT_EMULATION)
    message(STATUS "Emulation mode enabled - targets will use Renode instead of OpenOCD")
    message(STATUS "Renode platform: ${DMBOOT_RENODE_PLATFORM}")
    set(INSTALL_FIRMWARE_COMMAND ${CMAKE_COMMAND} -E copy ${MODULE_NAME}.elf ${CMAKE_BINARY_DIR}/renode_firmware.elf)
    set(INSTALL_FIRMWARE_COMMENT "Copying firmware for Renode: ${TARGET}...")
    set(CONNECT_COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/scripts/renode_connect.sh 
        ${CMAKE_BINARY_DIR}/renode_firmware.elf 
        ${TARGET}
        ${DMBOOT_RENODE_PLATFORM}
        ${DMBOOT_MCU_NAME}
        ${RENODE_SCRIPT_PATH})
    set(CONNECT_COMMENT "Starting Renode for ${TARGET}...")
else()
    set(INSTALL_FIRMWARE_COMMAND ${OPENOCD} -f ${OPENOCD_INTERFACE} -f ${OPENOCD_TARGET}
        -c "program ${MODULE_NAME}.elf verify reset exit")
    set(INSTALL_FIRMWARE_COMMENT "Installing firmware on ${TARGET}...")
    set(CONNECT_COMMAND ${OPENOCD} -f ${OPENOCD_INTERFACE} -f ${OPENOCD_TARGET})
    set(CONNECT_COMMENT "Connecting to ${TARGET} with OpenOCD...")
endif()

# Define install-firmware target
add_custom_target(install-firmware
    COMMAND ${INSTALL_FIRMWARE_COMMAND}
    DEPENDS ${MODULE_NAME}.elf
    COMMENT ${INSTALL_FIRMWARE_COMMENT}
)

# Define connect target
add_custom_target(connect
    COMMAND ${CONNECT_COMMAND}
    DEPENDS install-firmware
    COMMENT ${CONNECT_COMMENT}
)

# ======================================================================
#               Debugging Target (hardware mode only)
# ======================================================================
# Custom target for debugging with GDB (connects to OpenOCD)
add_custom_target(debug
    COMMAND ${ARM_GDB} -x ${CMAKE_BINARY_DIR}/gdb_init.gdb ${MODULE_NAME}.elf
    DEPENDS ${MODULE_NAME}.elf
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMENT "Starting GDB and connecting to OpenOCD..."
)
