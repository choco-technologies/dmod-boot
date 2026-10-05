#!/usr/bin/env python3
"""Turn a .dmvi image into a .dmvir - the same image with its pixels unpacked.

A .dmvi (dmview's image format, see dmview's docs/image-format.md) is a
56-byte header followed by the pixels, optionally packed with dmod's
compression (FastLZ). A .dmvir ("raw") is the same file with everything after
the header unpacked: the bytes a reader draws straight from, with nothing to
decode - e.g. the splash logo dmlcdtft shows as soon as the display is up.

Usage: dmvi_to_dmvir.py INPUT.dmvi OUTPUT.dmvir
"""
import struct
import sys

HEADER_SIZE = 56
MAGIC = b"DMVI"
FILE_SIZE_OFFSET = 8
COMPRESSION_OFFSET = 40
COMPRESSION_SIZE = 12
UNPACKED_SIZE_OFFSET = 52
FASTLZ_MAX_L2_DISTANCE = 8191


def fastlz_unpack(src, size):
    """FastLZ (level 1 and 2) decompression, as fastlz_decompress() in dmod."""
    level = (src[0] >> 5) + 1
    if level not in (1, 2):
        raise ValueError(f"unknown FastLZ level {level}")
    out = bytearray()
    ip = 1
    ctrl = src[0] & 31
    while True:
        if ctrl >= 32:
            length = (ctrl >> 5) - 1
            offset = (ctrl & 31) << 8
            ref = len(out) - offset - 1
            if length == 6:
                if level == 1:
                    length += src[ip]
                    ip += 1
                else:
                    while True:
                        code = src[ip]
                        ip += 1
                        length += code
                        if code != 255:
                            break
            code = src[ip]
            ip += 1
            ref -= code
            length += 3
            if level == 2 and code == 255 and offset == (31 << 8):
                offset = (src[ip] << 8) | src[ip + 1]
                ip += 2
                ref = len(out) - offset - FASTLZ_MAX_L2_DISTANCE - 1
            if ref < 0:
                raise ValueError("FastLZ reference before the start of the data")
            for _ in range(length):         # The match may overlap what it writes
                out.append(out[ref])
                ref += 1
        else:
            ctrl += 1
            out += src[ip:ip + ctrl]
            ip += ctrl
        if ip >= len(src):
            break
        ctrl = src[ip]
        ip += 1
    if len(out) != size:
        raise ValueError(f"unpacked {len(out)} bytes, the header says {size}")
    return bytes(out)


def to_raw(data):
    if len(data) < HEADER_SIZE or data[:4] != MAGIC:
        raise ValueError("not a .dmvi file")
    header = bytearray(data[:HEADER_SIZE])
    file_size, = struct.unpack_from("<I", header, FILE_SIZE_OFFSET)
    unpacked_size, = struct.unpack_from("<I", header, UNPACKED_SIZE_OFFSET)
    if file_size != len(data):
        raise ValueError(f"file is {len(data)} bytes, its header says {file_size}")
    compression = bytes(header[COMPRESSION_OFFSET:COMPRESSION_OFFSET + COMPRESSION_SIZE]).split(b"\0")[0].decode()
    body = data[HEADER_SIZE:]
    if compression == "fastlz":
        body = fastlz_unpack(body, unpacked_size)
    elif compression:
        raise ValueError(f"unsupported compression '{compression}'")
    struct.pack_into("<I", header, FILE_SIZE_OFFSET, HEADER_SIZE + len(body))
    header[COMPRESSION_OFFSET:COMPRESSION_OFFSET + COMPRESSION_SIZE] = bytes(COMPRESSION_SIZE)
    return bytes(header) + body


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    try:
        with open(sys.argv[1], "rb") as source:
            raw = to_raw(source.read())
    except (OSError, ValueError, IndexError) as error:
        print(f"dmvi_to_dmvir: {sys.argv[1]}: {error}", file=sys.stderr)
        return 1
    with open(sys.argv[2], "wb") as target:
        target.write(raw)
    return 0


if __name__ == "__main__":
    sys.exit(main())
