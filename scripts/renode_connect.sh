#!/bin/bash
# Script to launch Renode with GDB server for ARM Cortex-M emulation
# This script is called by the 'connect' target when DMBOOT_QEMU=ON

# Check if required parameters are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 <firmware.elf> <target_name> [platform_file]"
    exit 1
fi

FIRMWARE_FILE="$1"
TARGET_NAME="$2"
PLATFORM_FILE="${3:-$(dirname $0)/renode_platform.resc}"
BUILD_DIR=$(dirname "$FIRMWARE_FILE")

# Check if firmware file exists
if [ ! -f "$FIRMWARE_FILE" ]; then
    echo "Error: Firmware file not found: $FIRMWARE_FILE"
    exit 1
fi

echo "Starting Renode for ${TARGET_NAME} emulation..."
echo "Firmware: $FIRMWARE_FILE"
echo "Platform: $PLATFORM_FILE"
echo "GDB server will be available on localhost:3333"
echo ""

# Create a temporary Renode script that loads the firmware
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" << EOF
# Renode script for ${TARGET_NAME}
mach create "stm32f746"
machine LoadPlatformDescription @platforms/boards/stm32f7_discovery-kit.repl

# Load firmware
sysbus LoadELF @${FIRMWARE_FILE}

# Set up GDB server on port 3333 (compatible with OpenOCD)
machine StartGdbServer 3333 true

# Show analyzer for UART output
showAnalyzer sysbus.usart1

# Start emulation
start
EOF

echo "Renode script created at: $TEMP_SCRIPT"

# Launch Renode with the temporary script
# --disable-xwt: no GUI
# --console: interactive console
# --port -2: random telnet port (we don't use telnet)
renode --disable-xwt --console -e "include @${TEMP_SCRIPT}" &

RENODE_PID=$!
echo "Renode started with PID: $RENODE_PID"
echo "Waiting for Renode GDB server to be ready..."
sleep 3

# Keep the script running and forward signals to Renode
echo ""
echo "Firmware loaded and running in Renode."
echo "Press Ctrl+C to exit"
echo ""

# Cleanup on exit
cleanup() {
    echo "Stopping Renode..."
    kill $RENODE_PID 2>/dev/null
    rm -f "$TEMP_SCRIPT"
    exit
}

# Forward SIGINT and SIGTERM to Renode
trap cleanup INT TERM

# Wait for Renode to exit
wait $RENODE_PID
rm -f "$TEMP_SCRIPT"
