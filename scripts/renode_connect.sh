#!/bin/bash
# Script to launch Renode with GDB server for ARM Cortex-M emulation
# This script is called by the 'connect' target when DMBOOT_EMULATION=ON

# Check if required parameters are provided
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "Error: Missing required parameters"
    echo "Usage: $0 <firmware.elf> <target_name> <platform_repl> <machine_name>"
    exit 1
fi

FIRMWARE_FILE="$1"
TARGET_NAME="$2"
PLATFORM_REPL="$3"
MACHINE_NAME="$4"
BUILD_DIR=$(dirname "$FIRMWARE_FILE")

# Check if firmware file exists
if [ ! -f "$FIRMWARE_FILE" ]; then
    echo "Error: Firmware file not found: $FIRMWARE_FILE"
    exit 1
fi

echo "Starting Renode for ${TARGET_NAME} emulation..."
echo "Firmware: $FIRMWARE_FILE"
echo "Platform: ${PLATFORM_REPL}"
echo "Machine: ${MACHINE_NAME}"
echo "GDB server will be available on localhost:3333"
echo ""

# Create a temporary Renode script that loads the firmware
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" << EOF
# Renode script for ${TARGET_NAME}
mach create "${MACHINE_NAME}"
machine LoadPlatformDescription @${PLATFORM_REPL}

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

# Find Renode executable in PATH
RENODE_BIN=$(which renode 2>/dev/null)
if [ -z "$RENODE_BIN" ]; then
    echo "Error: renode not found in PATH"
    echo "Please ensure Renode is installed and in your PATH"
    exit 1
fi

# Get Renode installation directory (renode is typically a script)
RENODE_DIR=$(dirname "$RENODE_BIN")

# Launch Renode with the temporary script
# --disable-xwt: no GUI
# --console: interactive console
# --port -2: random telnet port (we don't use telnet)
# Change to Renode directory so platform files can be found
cd "$RENODE_DIR" && renode --disable-xwt --console -e "include @${TEMP_SCRIPT}" &

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
