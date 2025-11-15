# ======================================================================
#               CMake Targets Configuration
# ======================================================================
# This file defines all custom targets for the dmod-boot project
# including install-firmware, connect, debug, monitor, and monitor-gdb

# ======================================================================
#               GDB Init Script Configuration
# ======================================================================
# Generate GDB init script from template with target-specific variables
# Use QEMU-specific template in QEMU mode, otherwise use hardware template
if(DMBOOT_QEMU)
    set(GDB_INIT_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/configs/gdb/gdb_init_qemu.gdb.in")
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

if(DMBOOT_QEMU)
    message(STATUS "QEMU mode enabled - targets will use QEMU instead of OpenOCD")
    
    # In QEMU mode, install-firmware just copies the firmware to a known location
    add_custom_target(install-firmware
        COMMAND ${CMAKE_COMMAND} -E copy ${MODULE_NAME}.elf ${CMAKE_BINARY_DIR}/qemu_firmware.elf
        DEPENDS ${MODULE_NAME}.elf
        COMMENT "Copying firmware for QEMU: ${TARGET}..."
    )
    
    # In QEMU mode, connect launches QEMU with GDB server and loads firmware via GDB
    # We use a script that starts QEMU in background and then uses GDB to load the firmware
    add_custom_target(connect
        COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/scripts/qemu_connect.sh 
            ${CMAKE_BINARY_DIR}/qemu_firmware.elf 
            ${DMBOOT_QEMU_MACHINE} 
            ${DMBOOT_QEMU_CPU}
            ${TARGET}
        DEPENDS install-firmware
        COMMENT "Starting QEMU for ${TARGET}..."
    )
else()
    # Normal hardware mode with OpenOCD
    add_custom_target(install-firmware
        COMMAND ${OPENOCD} -f ${OPENOCD_INTERFACE} -f ${OPENOCD_TARGET}
            -c "program ${MODULE_NAME}.elf verify reset exit"
        DEPENDS ${MODULE_NAME}.elf
        COMMENT "Installing firmware on ${TARGET}..."
    )
    
    # Custom target for connecting to target with OpenOCD
    add_custom_target(connect
        COMMAND ${OPENOCD} -f ${OPENOCD_INTERFACE} -f ${OPENOCD_TARGET}
        COMMENT "Connecting to ${TARGET} with OpenOCD..."
    )
endif()

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
