#!/bin/bash
# Verify that expected log messages appear in Renode firmware execution
# Usage: verify_renode_logs.sh <log_file> <expected_logs_file>
#
# Lines in the expected_logs_file:
#   - Empty lines and lines starting with # are ignored.
#   - Lines starting with ! are "must NOT appear" patterns; the pattern
#     being checked is the text after the leading '!'.
#     Example: !HardFault_Handler invoked!
#             (checks that the text "HardFault_Handler invoked!" is absent)
#   - All other lines are "must appear" patterns.

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <log_file> <expected_logs_file>"
    exit 1
fi

LOG_FILE="$1"
EXPECTED_LOGS_FILE="$2"

if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file not found: $LOG_FILE"
    exit 1
fi

if [ ! -f "$EXPECTED_LOGS_FILE" ]; then
    echo "Error: Expected logs file not found: $EXPECTED_LOGS_FILE"
    exit 1
fi

echo "Verifying logs from: $LOG_FILE"
echo "Expected logs from: $EXPECTED_LOGS_FILE"
echo ""

# Read expected logs line by line
ALL_FOUND=true
while IFS= read -r expected_log || [ -n "$expected_log" ]; do
    # Skip empty lines and comments
    if [ -z "$expected_log" ] || [[ "$expected_log" =~ ^#.* ]]; then
        continue
    fi

    # Lines starting with ! are "must NOT appear" patterns
    if [[ "$expected_log" =~ ^!.* ]]; then
        pattern="${expected_log:1}"
        echo -n "Checking absent: '$pattern' ... "
        if grep -q "$pattern" "$LOG_FILE"; then
            echo "✗ FOUND (should be absent)"
            ALL_FOUND=false
        else
            echo "✓ ABSENT"
        fi
    else
        echo -n "Checking for: '$expected_log' ... "
        if grep -q "$expected_log" "$LOG_FILE"; then
            echo "✓ FOUND"
        else
            echo "✗ NOT FOUND"
            ALL_FOUND=false
        fi
    fi
done < "$EXPECTED_LOGS_FILE"

echo ""
if [ "$ALL_FOUND" = true ]; then
    echo "✓✓✓ SUCCESS: All expected logs found!"
    echo "✓ Firmware executed successfully in Renode"
    echo "✓ monitor-gdb successfully read logs via GDB"
    exit 0
else
    echo "✗✗✗ FAILURE: Some expected logs were not found"
    echo "✗ Firmware may not have executed properly"
    exit 1
fi
