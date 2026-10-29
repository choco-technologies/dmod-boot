#!/usr/bin/env python3
"""Makes a bank image: the header of dmsel.h in front of the code.

The code (objcopy -O binary of an ELF linked at <bank start> + 0x200) starts with the vector table. The image is
512 bytes of the header area (the header, then 0xFF) and the code, padded to a whole word.

  dmsel_mkimage.py code.bin image.bin --version 3 [--capacity 0x60000]
"""
import argparse, struct, sys, zlib

MAGIC = 0x4B424D44
HEADER = struct.Struct('<IHHIIIIII')    # magic, header_version, header_size, image_size, version, image_crc, entry_offset, flags, header_crc
AREA = 512

def make(code, version, capacity=None):
    code = code + b'\xff' * (-len(code) % 4)
    size = AREA + len(code)
    if capacity is not None and size > capacity:
        raise SystemExit(f'the image ({size} bytes) does not fit the bank ({capacity})')
    body = bytearray(b'\xff' * AREA) + code
    image_crc = zlib.crc32(bytes(body[HEADER.size:size])) & 0xFFFFFFFF
    head = struct.pack('<IHHIIIII', MAGIC, 1, HEADER.size, size, version, image_crc, AREA, 0)
    head += struct.pack('<I', zlib.crc32(head) & 0xFFFFFFFF)
    body[:HEADER.size] = head
    # the CRC of the image covers the header area from header_size on, so it has to be computed after the header: it does
    # not include the header itself
    return bytes(body)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('code'); ap.add_argument('image')
    ap.add_argument('--version', type=lambda x: int(x, 0), required=True)
    ap.add_argument('--capacity', type=lambda x: int(x, 0))
    a = ap.parse_args()
    out = make(open(a.code, 'rb').read(), a.version, a.capacity)
    open(a.image, 'wb').write(out)
    print(f'{a.image}: {len(out)} bytes, version {a.version}')
