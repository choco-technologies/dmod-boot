#!/bin/bash
# Script to launch QEMU with GDB server for STM32F746 emulation
# This script is called by the 'connect' target when DMBOOT_QEMU=ON

# Check if firmware file is provided
if [ -z "$1" ]; then
    echo "Error: No firmware file specified"
    echo "Usage: $0 <firmware.elf>"
    exit 1
fi

FIRMWARE_FILE="$1"
BUILD_DIR=$(dirname "$FIRMWARE_FILE")

# Check if firmware file exists
if [ ! -f "$FIRMWARE_FILE" ]; then
    echo "Error: Firmware file not found: $FIRMWARE_FILE"
    exit 1
fi

echo "Starting QEMU for STM32F746 emulation..."
echo "Firmware: $FIRMWARE_FILE"
echo "GDB server will be available on localhost:3333"
echo ""

# Launch QEMU with:
# - mps2-an500: ARM MPS2 with AN500 FPGA image for Cortex-M7
# - GDB server on port 3333 (compatible with OpenOCD)
# - No graphics
# - Serial output to stdio
# - Semihosting enabled for printf debugging
# - Halt at startup (-S) to allow GDB to load firmware
qemu-system-arm \
    -machine mps2-an500 \
    -cpu cortex-m7 \
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
