#!/bin/sh
# Builds the test images of the banks A and B: build.sh <output dir> <version A> <version B>
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?output directory}; mkdir -p "$OUT"
build() {   # <name> <bank index> <vectors address> <version>
    arm-none-eabi-gcc -mcpu=cortex-m7 -mthumb -Os -ffreestanding -nostdlib -nostartfiles -Wall -Wextra -std=gnu11 \
        -DBANK_INDEX=$2 -I"$HERE/../../include" -Wl,--defsym=BANK_ORIGIN=$3 -T"$HERE/bank.ld" -Wl,--gc-sections \
        -o "$OUT/$1.elf" "$HERE/start.c" "$HERE/main.c" "$HERE/libc.c" -lgcc
    arm-none-eabi-objcopy -O binary "$OUT/$1.elf" "$OUT/$1.code.bin"
    python3 -I "$HERE/../../tools/dmsel_mkimage.py" "$OUT/$1.code.bin" "$OUT/$1.bin" --version "$4" --capacity 0x60000
}
build bank_a 0 0x08020200 "${2:-1}"
build bank_b 1 0x08080200 "${3:-2}"
