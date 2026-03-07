#!/bin/bash
# run_renode_tests.sh - Run Renode emulation tests for dmod-boot
#
# This script builds the stm32f746g-disco firmware with Renode emulation mode,
# starts Renode, runs monitor-gdb to capture firmware logs, and verifies that
# the expected log messages appear.  In particular it catches the hard-fault
# that occurs when .dmod.inputs is not correctly copied to RAM at startup
# (which prevents Dmod_EnterCritical and other output function pointers from
# being connected when modules are loaded at runtime).
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
CONNECT_TIMEOUT=120
MONITOR_TIMEOUT=60

echo "=============================================="
echo " dmod-boot Renode emulation tests"
echo " Board: $BOARD"
echo "=============================================="
echo "Source dir : $SOURCE_DIR"
echo "Build dir  : $BUILD_DIR"
echo "Board      : $BOARD"
echo ""

# Cleanup helper – kill any lingering background processes on exit
cleanup() {
    if [ -n "$CONNECT_PID" ] && ps -p "$CONNECT_PID" > /dev/null 2>&1; then
        kill "$CONNECT_PID" 2>/dev/null || true
    fi
    if [ -n "$MONITOR_PID" ] && ps -p "$MONITOR_PID" > /dev/null 2>&1; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# -------------------------------------------------------
# Step 1 – Build firmware with emulation mode enabled
# -------------------------------------------------------
echo "[1/4] Building firmware (BOARD=$BOARD, DMBOOT_EMULATION=ON)..."
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
timeout "$CONNECT_TIMEOUT" cmake --build "$BUILD_DIR" --target connect > "$CONNECT_LOG" 2>&1 &
CONNECT_PID=$!

echo "Waiting for Renode GDB server to start (PID $CONNECT_PID)..."
sleep 5

if ! ps -p "$CONNECT_PID" > /dev/null 2>&1; then
    echo "✗ Renode failed to start"
    echo "--- connect.log ---"
    cat "$CONNECT_LOG"
    exit 1
fi
echo "✓ Renode started successfully"
echo ""

# -------------------------------------------------------
# Step 4 – Run monitor-gdb and verify firmware logs
# -------------------------------------------------------
echo "[4/4] Running monitor-gdb to capture firmware logs..."
MONITOR_LOG="$BUILD_DIR/monitor.log"
timeout "$MONITOR_TIMEOUT" cmake --build "$BUILD_DIR" --target monitor-gdb > "$MONITOR_LOG" 2>&1 &
MONITOR_PID=$!

# Give the firmware time to boot and produce log output
echo "Waiting ${MONITOR_TIMEOUT}s for firmware to boot..."
sleep "$MONITOR_TIMEOUT"

echo "Monitor output:"
cat "$MONITOR_LOG"
echo ""

# Also show the Renode connect log for diagnostics
echo "--- connect.log (last 40 lines) ---"
tail -40 "$CONNECT_LOG" || true
echo ""

# Verify expected log messages
bash "$VERIFY_SCRIPT" "$MONITOR_LOG" "$EXPECTED_LOGS"
VERIFY_STATUS=$?

echo ""
echo "=============================================="
if [ "$VERIFY_STATUS" -eq 0 ]; then
    echo " Renode emulation tests PASSED"
else
    echo " Renode emulation tests FAILED"
fi
echo "=============================================="

exit "$VERIFY_STATUS"
