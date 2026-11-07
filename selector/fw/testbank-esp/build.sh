#!/bin/sh
# Builds the test image of a bank for the ESP32-S3 (one for both banks): build.sh <output dir> [version]
# Result: <output dir>/bank.bin, for the bank A at 0x100000 and/or the bank B at 0x400000 of the flash
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?output directory}; mkdir -p "$OUT"
PREFIX=${DMSEL_XTENSA_PREFIX:-xtensa-esp32s3-elf-}
${PREFIX}gcc -mlongcalls -mtext-section-literals -Os -ffreestanding -nostdlib -nostartfiles -Wall -Wextra -std=gnu11 \
    -DDMSEL_TABLE_ADDRESS=0x3fcd9700u -I"$HERE/../../include" -T"$HERE/bank.ld" -Wl,--gc-sections \
    -Wl,-Map="$OUT/bank.map" -o "$OUT/bank.elf" "$HERE/start.c" "$HERE/main.c" "$HERE/../libc_min.c" -lgcc
${PREFIX}objcopy -O binary "$OUT/bank.elf" "$OUT/bank.code.bin"
python3 -I "$HERE/../../tools/dmsel_mkimage.py" "$OUT/bank.code.bin" "$OUT/bank.bin" --version "${2:-1}" --capacity 0x2F0000
${PREFIX}size "$OUT/bank.elf"
