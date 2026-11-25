#!/bin/bash
# Runs the ESP32-S3 tests in QEMU: run_qemu_tests.sh <build-dir of the elecrow-dis08070h firmware> <qemu install dir>
# (the build: cmake --build <dir> --target selector all; the QEMU: scripts/qemu/build-qemu.sh <dir>)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMG="$(mktemp -d)"; trap 'rm -rf "$IMG"' EXIT
python3 "$HERE/qemu/make-images.py" "$1" "$IMG"
python3 "$HERE/qemu/test_qemu_esp32s3.py" "$2" "$IMG"
