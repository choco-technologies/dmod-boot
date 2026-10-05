#!/bin/bash
# run_renode_tests.sh - Run Renode emulation tests for dmod-boot
#
# This script reproduces the Renode CI tests locally.
# It builds the firmware with emulation mode, starts Renode, runs monitor-gdb
# to capture firmware logs, verifies the expected log messages, checks that
# the shell answers on the console UART, checks the SD card (an image with a
# FAT16 partition inserted in the card slot: read, write, remount), checks the
# LCD (the display shows the splash screen at boot, then what lcdtest draws),
# checks the touch panel (touches injected through the Renode monitor reach
# touchtest) and - when it can open a TAP interface - checks the network
# (DHCP, ping both ways, telnet, DNS lookup with the server from the lease).
#
# Test tools the steps need (lcdtest, touchtest) come from configs/renode/test-modules.dmd,
# added to the firmware through DMBOOT_EXTRA_FLASH_DMD_FILES.
#
# The network step needs root and /dev/net/tun (in Docker:
# --cap-add=NET_ADMIN --device=/dev/net/tun). Without them it is skipped,
# unless DMBOOT_TEST_NETWORK=1 makes it mandatory (as CI does).
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
SDCARD_IMAGE_SCRIPT="$SOURCE_DIR/scripts/make_sdcard_image.py"
SDCARD_TEST_SCRIPT="$SOURCE_DIR/scripts/test_renode_sdcard.py"
SDCARD_IMAGE="$BUILD_DIR/sdcard.img"
LCD_TEST_SCRIPT="$SOURCE_DIR/scripts/test_renode_lcd.py"
LCD_FRAME_FILE="$BUILD_DIR/lcd_frame.bin"
SPLASH_LOGO="$BUILD_DIR/eviews/splash_logo.dmvir"
TEST_MODULES_DMD="$SOURCE_DIR/configs/renode/test-modules.dmd"
TOUCH_TEST_SCRIPT="$SOURCE_DIR/scripts/test_renode_touch.py"
MONITOR_PORT=3457
NETWORK_TEST_SCRIPT="$SOURCE_DIR/scripts/test_renode_network.py"
TAP_INTERFACE=tap0

# Timeouts (seconds)
# Upper bound only: step 4 stops as soon as every expected line is captured
MONITOR_TIMEOUT=300
UART_TIMEOUT=90
SDCARD_TIMEOUT=90
LCD_TIMEOUT=120
TOUCH_TIMEOUT=120
NETWORK_TIMEOUT=120
# Renode has to outlive the monitor and the UART, SD card, LCD, touch and network tests
TESTS_TIMEOUT=$((UART_TIMEOUT + SDCARD_TIMEOUT + LCD_TIMEOUT + TOUCH_TIMEOUT + NETWORK_TIMEOUT))
CONNECT_TIMEOUT=$((MONITOR_TIMEOUT + TESTS_TIMEOUT + 60))

# The network test needs a TAP interface: root and /dev/net/tun
NETWORK_TEST=0
if [ "$(id -u)" -eq 0 ] && [ -c /dev/net/tun ]; then
    NETWORK_TEST=1
elif [ "${DMBOOT_TEST_NETWORK:-0}" = "1" ]; then
    echo "✗ DMBOOT_TEST_NETWORK=1, but the network test needs root and /dev/net/tun"
    exit 1
fi
RENODE_TAP=""
if [ "$NETWORK_TEST" -eq 1 ]; then
    RENODE_TAP="$TAP_INTERFACE"
fi

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
echo "[1/9] Building firmware with emulation mode enabled..."
# The card image has to exist when CMake writes the Renode script
mkdir -p "$BUILD_DIR"
python3 "$SDCARD_IMAGE_SCRIPT" "$SDCARD_IMAGE"
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DBOARD="$BOARD" \
      -DDMBOOT_EMULATION=ON \
      -DDMBOOT_RENODE_WAIT_FOR_GDB=ON \
      -DDMBOOT_RENODE_UART_PORT="$UART_PORT" \
      -DDMBOOT_RENODE_TAP="$RENODE_TAP" \
      -DDMBOOT_RENODE_SDCARD="$SDCARD_IMAGE" \
      -DDMBOOT_RENODE_LCD_CAPTURE="$LCD_FRAME_FILE" \
      -DDMBOOT_RENODE_MONITOR_PORT="$MONITOR_PORT" \
      -DDMBOOT_EXTRA_FLASH_DMD_FILES="$TEST_MODULES_DMD" \
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
echo "[2/9] Testing install-firmware target..."
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
echo "[3/9] Starting Renode emulation..."
CONNECT_LOG="$BUILD_DIR/connect.log"
# No frame of an earlier run may pass for one of this run
rm -f "$LCD_FRAME_FILE"
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
echo "[4/9] Running monitor-gdb to capture firmware logs..."
MONITOR_LOG="$BUILD_DIR/monitor.log"
# The monitor stays attached through steps 5 to 9: it keeps resuming the
# target between its reads, whereas stopping it mid-read could leave the
# target halted
timeout "$((MONITOR_TIMEOUT + TESTS_TIMEOUT))" cmake --build "$BUILD_DIR" --target monitor-gdb > "$MONITOR_LOG" 2>&1 &
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
echo "[5/9] Checking the shell on the console UART..."
UART_STATUS=0
python3 "$UART_TEST_SCRIPT" --port "$UART_PORT" --timeout "$UART_TIMEOUT" || UART_STATUS=$?
echo ""

# -------------------------------------------------------
# Step 6 – Check the SD card: read, write, remount
# -------------------------------------------------------
echo "[6/9] Checking the SD card..."
SDCARD_STATUS=0
if [ "$UART_STATUS" -ne 0 ]; then
    echo "Skipped: the shell on the console UART does not work"
else
    python3 "$SDCARD_TEST_SCRIPT" --port "$UART_PORT" --timeout "$SDCARD_TIMEOUT" || SDCARD_STATUS=$?
fi
echo ""

# -------------------------------------------------------
# Step 7 – Check the LCD: the display shows what lcdtest draws
# -------------------------------------------------------
echo "[7/9] Checking the LCD..."
LCD_STATUS=0
if [ "$UART_STATUS" -ne 0 ]; then
    echo "Skipped: the shell on the console UART does not work"
else
    python3 "$LCD_TEST_SCRIPT" --frame-file "$LCD_FRAME_FILE" --splash-logo "$SPLASH_LOGO" \
        --port "$UART_PORT" --timeout "$LCD_TIMEOUT" || LCD_STATUS=$?
fi
echo ""

# -------------------------------------------------------
# Step 8 – Check the touch panel: injected touches reach touchtest
# -------------------------------------------------------
echo "[8/9] Checking the touch panel..."
TOUCH_STATUS=0
if [ "$UART_STATUS" -ne 0 ]; then
    echo "Skipped: the shell on the console UART does not work"
else
    python3 "$TOUCH_TEST_SCRIPT" --port "$UART_PORT" --monitor-port "$MONITOR_PORT" \
        --timeout "$TOUCH_TIMEOUT" || TOUCH_STATUS=$?
fi
echo ""

# -------------------------------------------------------
# Step 9 – Check the network: DHCP, ping both ways, telnet, DNS
# -------------------------------------------------------
echo "[9/9] Checking the network..."
NETWORK_STATUS=0
if [ "$UART_STATUS" -ne 0 ]; then
    echo "Skipped: the shell on the console UART does not work"
elif [ "$NETWORK_TEST" -eq 1 ]; then
    python3 "$NETWORK_TEST_SCRIPT" --tap "$TAP_INTERFACE" --uart-port "$UART_PORT" \
        --timeout "$NETWORK_TIMEOUT" || NETWORK_STATUS=$?
else
    echo "Skipped: needs root and /dev/net/tun (set DMBOOT_TEST_NETWORK=1 to require it)"
fi
pkill -f dmlog_monitor 2>/dev/null || true

TEST_STATUS=$((UART_STATUS | SDCARD_STATUS | LCD_STATUS | TOUCH_STATUS | NETWORK_STATUS))
echo ""
echo "=============================================="
if [ "$TEST_STATUS" -eq 0 ]; then
    echo " Renode emulation tests PASSED"
else
    echo " Renode emulation tests FAILED"
    # The monitor kept logging during steps 5 to 9 - whatever stopped the
    # shell, the SD card, the LCD or the network (e.g. a stack overflow) is at
    # the end of its log
    echo "--- monitor.log (tail) ---"
    tail -n 40 "$MONITOR_LOG"
    echo "--- connect.log (tail) ---"
    tail -n 40 "$CONNECT_LOG"
fi
echo "=============================================="

exit "$TEST_STATUS"
