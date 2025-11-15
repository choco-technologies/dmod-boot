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
if(DMBOOT_QEMU)
    set(GDB_INIT_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/configs/gdb/gdb_init_renode.gdb.in")
else()
    set(GDB_INIT_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/configs/gdb/gdb_init.gdb.in")
endif()

configure_file(
    ${GDB_INIT_TEMPLATE}
    ${CMAKE_BINARY_DIR}/gdb_init.gdb
    @ONLY
)

# ======================================================================
#               Firmware Installation and Connection Targets
# ======================================================================

# Configure install-firmware command based on mode
if(DMBOOT_QEMU)
    message(STATUS "Emulation mode enabled - targets will use Renode instead of OpenOCD")
    set(INSTALL_FIRMWARE_COMMAND ${CMAKE_COMMAND} -E copy ${MODULE_NAME}.elf ${CMAKE_BINARY_DIR}/renode_firmware.elf)
    set(INSTALL_FIRMWARE_COMMENT "Copying firmware for Renode: ${TARGET}...")
    set(CONNECT_COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/scripts/renode_connect.sh 
        ${CMAKE_BINARY_DIR}/renode_firmware.elf 
        ${TARGET})
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
