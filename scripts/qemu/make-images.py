#!/usr/bin/env python3
"""Makes the images QEMU needs for an ESP32-S3 board with the 4 MB flash and the octal PSRAM of the Elecrow DIS08070H.

  make-images.py <build-dir> <out-dir>

  <out-dir>/flash.bin  4 MB: the selector at 0 and the bank A at 0x20000 (the layout of the board: board.cmake)
  <out-dir>/efuse.bin  the eFuses with PSRAM_CAP = 2 (octal, 8 MB): without it the ROM and the firmware see no PSRAM
"""
import os
import struct
import sys

FLASH_SIZE = 0x400000
BANK_A = 0x20000
EFUSE_SIZE = 336            # the blocks of the ESP32-S3 (struct ESPEfuseBlocks of QEMU)
RD_MAC_SPI_SYS_4 = 40       # byte offset of the word with PSRAM_CAP (bits 3..4)

build, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

flash = bytearray(b"\xff" * FLASH_SIZE)
with open(os.path.join(build, "selector", "dmsel.bin"), "rb") as f:
    sel = f.read()
with open(os.path.join(build, "dmboot_bank_A.bin"), "rb") as f:
    bank = f.read()
assert len(sel) <= BANK_A and BANK_A + len(bank) <= FLASH_SIZE
flash[0:len(sel)] = sel
flash[BANK_A:BANK_A + len(bank)] = bank
with open(os.path.join(out, "flash.bin"), "wb") as f:
    f.write(flash)

efuse = bytearray(EFUSE_SIZE)
struct.pack_into("<I", efuse, RD_MAC_SPI_SYS_4, 2 << 3)
with open(os.path.join(out, "efuse.bin"), "wb") as f:
    f.write(efuse)
