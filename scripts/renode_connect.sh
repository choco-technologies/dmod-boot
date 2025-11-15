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
RENODE_SCRIPT="$5"
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
echo "Renode script: ${RENODE_SCRIPT}"
echo "GDB server will be available on localhost:3333"
echo ""

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
# --hide-monitor: no console (headless mode)
# --port -2: random telnet port (we don't use telnet)
# Change to Renode directory so platform files can be found
cd "$RENODE_DIR" && renode --disable-xwt --hide-monitor -e "include @${RENODE_SCRIPT}" &

RENODE_PID=$!
echo "Renode started with PID: $RENODE_PID"
echo "Waiting for Renode GDB server to be ready..."
sleep 3

# Keep the script running and forward signals to Renode
echo ""
echo "Firmware loaded and running in Renode."
echo "Press Ctrl+C to exit"
echo ""

# Wait for Renode to exit
wait $RENODE_PID
