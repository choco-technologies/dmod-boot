#!/bin/bash
# run_renode_tests.sh - Run Renode emulation tests for dmod-boot
#
# This script reproduces the Renode CI tests locally.
# It builds the firmware with emulation mode, starts Renode, runs monitor-gdb
# to capture firmware logs, and verifies the expected log messages.
#
# Usage:
#   ./scripts/run_renode_tests.sh [SOURCE_DIR [BUILD_DIR]]
#
#   SOURCE_DIR  Path to the project root.
#               Defaults to the parent directory of this script.
#   BUILD_DIR   Path to the build directory.
#               Defaults to SOURCE_DIR/build.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${2:-$SOURCE_DIR/build}"

BOARD="stm32f746g-disco"
EXPECTED_LOGS="$SOURCE_DIR/configs/renode/expected_logs.txt"
VERIFY_SCRIPT="$SOURCE_DIR/scripts/verify_renode_logs.sh"

# Timeouts (seconds)
CONNECT_TIMEOUT=90
MONITOR_TIMEOUT=60

echo "=============================================="
echo " dmod-boot Renode emulation tests"
echo "=============================================="
echo "Source dir : $SOURCE_DIR"
echo "Build dir  : $BUILD_DIR"
echo "Board      : $BOARD"
echo ""

# -------------------------------------------------------
# Step 1 – Build firmware with emulation mode enabled
# -------------------------------------------------------
echo "[1/4] Building firmware with emulation mode enabled..."
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DBOARD="$BOARD" \
      -DDMBOOT_EMULATION=ON \
      -S "$SOURCE_DIR" \
      -B "$BUILD_DIR"
cmake --build "$BUILD_DIR" --config Debug
echo "✓ Build completed"
echo ""

# -------------------------------------------------------
# Step 2 – Verify install-firmware target
# -------------------------------------------------------
echo "[2/4] Testing install-firmware target..."
cmake --build "$BUILD_DIR" --target install-firmware
if [ ! -f "$BUILD_DIR/renode_firmware.elf" ]; then
    echo "✗ renode_firmware.elf not found after install-firmware"
    exit 1
fi
ls -lh "$BUILD_DIR/renode_firmware.elf"
echo "✓ install-firmware target works correctly"
echo ""

# -------------------------------------------------------
# Step 3 – Start Renode in the background
# -------------------------------------------------------
echo "[3/4] Starting Renode emulation..."
CONNECT_LOG="$BUILD_DIR/connect.log"
cmake --build "$BUILD_DIR" --target connect &
CONNECT_PID=$!

sleep 5  # Give Renode some time to start

# -------------------------------------------------------
# Step 4 – Run monitor-gdb to capture logs
# -------------------------------------------------------
echo "[4/4] Running monitor-gdb to capture logs..."
MONITOR_LOG="$BUILD_DIR/monitor.log"
cmake --build "$BUILD_DIR" --target monitor-gdb 
MONITOR_PID=$!

# Wait for monitor-gdb to finish
sleep $MONITOR_TIMEOUT
