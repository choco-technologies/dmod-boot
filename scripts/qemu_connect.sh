#!/bin/bash
# Script to launch QEMU with GDB server for ARM Cortex-M emulation
# This script is called by the 'connect' target when DMBOOT_QEMU=ON

# Check if all required parameters are provided
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 <firmware.elf> <qemu_machine> <qemu_cpu> <target_name>"
    exit 1
fi

FIRMWARE_FILE="$1"
QEMU_MACHINE="$2"
QEMU_CPU="$3"
TARGET_NAME="$4"
BUILD_DIR=$(dirname "$FIRMWARE_FILE")

# Check if firmware file exists
if [ ! -f "$FIRMWARE_FILE" ]; then
    echo "Error: Firmware file not found: $FIRMWARE_FILE"
    exit 1
fi

echo "Starting QEMU for ${TARGET_NAME} emulation..."
echo "Firmware: $FIRMWARE_FILE"
echo "QEMU Machine: $QEMU_MACHINE"
echo "QEMU CPU: $QEMU_CPU"
echo "GDB server will be available on localhost:3333"
echo ""

# Launch QEMU with:
# - Machine and CPU type from configuration
# - GDB server on port 3333 (compatible with OpenOCD)
# - No graphics
# - Serial output to stdio
# - Semihosting enabled for printf debugging
# - Halt at startup (-S) to allow GDB to load firmware
qemu-system-arm \
    -machine ${QEMU_MACHINE} \
    -cpu ${QEMU_CPU} \
    -nographic \
    -serial mon:stdio \
    -gdb tcp::3333 \
    -S \
    -semihosting-config enable=on,target=native &

QEMU_PID=$!
echo "QEMU started with PID: $QEMU_PID"
echo "Waiting for QEMU GDB server to be ready..."
sleep 2

# Use GDB to load the firmware and start execution
echo "Loading firmware via GDB..."
(
    # Run GDB in background to load and start firmware
    arm-none-eabi-gdb -batch -x "$BUILD_DIR/gdb_init.gdb" "$FIRMWARE_FILE" &
    GDB_PID=$!
    
    # Wait a bit for GDB to connect and load
    sleep 3
    
    # Check if GDB is still running (it continues with the firmware)
    if kill -0 $GDB_PID 2>/dev/null; then
        echo "GDB connected and continuing execution..."
    fi
) &

# Give GDB time to load the firmware
sleep 5

# Keep the script running and forward signals to QEMU
echo ""
echo "Firmware loaded and running."
echo "Press Ctrl+C to exit"
echo ""

# Forward SIGINT and SIGTERM to QEMU
trap "kill $QEMU_PID 2>/dev/null; exit" INT TERM

# Wait for QEMU to exit
wait $QEMU_PID
