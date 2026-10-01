#!/bin/bash
# run_renode_tests.sh - Run Renode emulation tests for dmod-boot
#
# This script reproduces the Renode CI tests locally.
# It builds the firmware with emulation mode, starts Renode, runs monitor-gdb
# to capture firmware logs, verifies the expected log messages, and then
# checks that the shell answers on the console UART.
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
UART_TEST_SCRIPT="$SOURCE_DIR/scripts/test_renode_uart.py"
UART_PORT=3456

# Timeouts (seconds)
# Upper bound only: step 4 stops as soon as every expected line is captured
MONITOR_TIMEOUT=300
UART_TIMEOUT=90
# Renode has to outlive both the monitor and the UART test
CONNECT_TIMEOUT=$((MONITOR_TIMEOUT + UART_TIMEOUT + 60))

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
echo "[1/5] Building firmware with emulation mode enabled..."
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DBOARD="$BOARD" \
      -DDMBOOT_EMULATION=ON \
      -DDMBOOT_RENODE_WAIT_FOR_GDB=ON \
      -DDMBOOT_RENODE_UART_PORT="$UART_PORT" \
      -S "$SOURCE_DIR" \
      -B "$BUILD_DIR"
cmake --build "$BUILD_DIR" --config Debug
# The boot log is much larger than the 8 KiB dmlog ring, so the machine waits
# for monitor-gdb to attach (DMBOOT_RENODE_WAIT_FOR_GDB) - build the monitor
# now, so it does not eat into the monitoring time
cmake --build "$BUILD_DIR" --target build_dmlog_monitor extract_ring_buffer_config
echo "✓ Build completed"
echo ""

# -------------------------------------------------------
# Step 2 – Verify install-firmware target
# -------------------------------------------------------
echo "[2/5] Testing install-firmware target..."
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
echo "[3/5] Starting Renode emulation..."
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
echo "[4/5] Running monitor-gdb to capture firmware logs..."
MONITOR_LOG="$BUILD_DIR/monitor.log"
# The monitor stays attached through step 5: it keeps resuming the target
# between its reads, whereas stopping it mid-read could leave the target halted
timeout "$((MONITOR_TIMEOUT + UART_TIMEOUT))" cmake --build "$BUILD_DIR" --target monitor-gdb > "$MONITOR_LOG" 2>&1 &
MONITOR_PID=$!

# Wait until every expected line has been captured, or MONITOR_TIMEOUT
MONITOR_DEADLINE=$((SECONDS + MONITOR_TIMEOUT))
while [ "$SECONDS" -lt "$MONITOR_DEADLINE" ] && kill -0 "$MONITOR_PID" 2>/dev/null; do
    if bash "$VERIFY_SCRIPT" "$MONITOR_LOG" "$EXPECTED_LOGS" > /dev/null 2>&1; then
        break
    fi
    sleep 2
done

echo "Monitor output:"
cat "$MONITOR_LOG"
echo ""

# Verify expected log messages
bash "$VERIFY_SCRIPT" "$MONITOR_LOG" "$EXPECTED_LOGS"
echo ""

# -------------------------------------------------------
# Step 5 – Check that the shell answers on the console UART
# -------------------------------------------------------
echo "[5/5] Checking the shell on the console UART..."
UART_STATUS=0
python3 "$UART_TEST_SCRIPT" --port "$UART_PORT" --timeout "$UART_TIMEOUT" || UART_STATUS=$?
pkill -f dmlog_monitor 2>/dev/null || true

echo ""
echo "=============================================="
if [ "$UART_STATUS" -eq 0 ]; then
    echo " Renode emulation tests PASSED"
else
    echo " Renode emulation tests FAILED"
    # The monitor kept logging during step 5 - whatever stopped the shell
    # (e.g. a stack overflow) is at the end of its log
    echo "--- monitor.log (tail) ---"
    tail -n 40 "$MONITOR_LOG"
    echo "--- connect.log (tail) ---"
    tail -n 40 "$CONNECT_LOG"
fi
echo "=============================================="

exit "$UART_STATUS"
