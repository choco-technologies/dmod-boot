#!/usr/bin/env python3
"""Turn a .dmvi image into a .dmvir - the same image with its pixels unpacked.

A .dmvi (dmview's image format, see dmview's docs/image-format.md) is a
56-byte header followed by the pixels, optionally packed with dmod's
compression (FastLZ). A .dmvir ("raw") is the same file with everything after
the header unpacked: the bytes a reader draws straight from, with nothing to
decode - e.g. the splash logo dmlcdtft shows as soon as the display is up.

With --rotate DEGREES (0, 90, 180, 270, clockwise) the image is turned as well: for a display
that is used turned (the logo is drawn into the frame buffer as the panel scans it, so it has to
be turned the way the views are). RGB565, ARGB8888 and RGB565A8 images can be turned.

Usage: dmvi_to_dmvir.py [--rotate DEGREES] INPUT.dmvi OUTPUT.dmvir
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

WIDTH_OFFSET = 12
HEIGHT_OFFSET = 14
FORMAT_OFFSET = 16
STRIDE_OFFSET = 20
PIXELS_OFFSET = 24
ALPHA_STRIDE_OFFSET = 28
ALPHA_OFFSET = 32
FORMAT_RGB565 = 1
FORMAT_ARGB8888 = 2
FORMAT_RGB565A8 = 3
BYTES_PER_PIXEL = {FORMAT_RGB565: 2, FORMAT_ARGB8888: 4, FORMAT_RGB565A8: 2}


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


def turn(rows, width, height, degrees):
    """The rows (lists of pixels, width x height) turned clockwise by `degrees`: the new rows."""
    if degrees == 0:
        return rows
    if degrees == 90:       # the new pixel (x, y) is the old one (y, height - 1 - x)
        return [[rows[height - 1 - x][y] for x in range(height)] for y in range(width)]
    if degrees == 180:
        return [row[::-1] for row in rows[::-1]]
    return [[rows[x][width - 1 - y] for x in range(height)] for y in range(width)]      # 270


def read_rows(data, offset, stride, width, height, size):
    return [[bytes(data[offset + y * stride + x * size:offset + y * stride + (x + 1) * size]) for x in range(width)]
            for y in range(height)]


def pack_rows(rows, size, stride):
    """The rows as bytes, each padded to `stride`"""
    out = bytearray()
    for row in rows:
        line = b"".join(row)
        out += line + bytes(stride - len(line))
    return out


def rotate(raw, degrees):
    """An unpacked .dmvi (a .dmvir) turned clockwise by `degrees`"""
    if degrees == 0:
        return raw
    header = bytearray(raw[:HEADER_SIZE])
    width, height = struct.unpack_from("<HH", header, WIDTH_OFFSET)
    pixel_format = header[FORMAT_OFFSET]
    if pixel_format not in BYTES_PER_PIXEL:
        raise ValueError(f"an image of the format {pixel_format} cannot be turned (RGB565, ARGB8888 and RGB565A8 can)")
    size = BYTES_PER_PIXEL[pixel_format]
    stride, pixels = struct.unpack_from("<II", header, STRIDE_OFFSET)
    new_pixels = turn(read_rows(raw, pixels, stride, width, height, size), width, height, degrees)
    new_width, new_height = (height, width) if degrees in (90, 270) else (width, height)
    new_stride = (new_width * size + 3) & ~3
    body = pack_rows(new_pixels, size, new_stride)
    alpha_stride = alpha = 0
    if pixel_format == FORMAT_RGB565A8:
        old_alpha_stride, old_alpha = struct.unpack_from("<II", header, ALPHA_STRIDE_OFFSET)
        planes = [[bytes([v]) for v in raw[old_alpha + y * old_alpha_stride:old_alpha + y * old_alpha_stride + width]]
                  for y in range(height)]
        alpha_stride = (new_width + 3) & ~3
        alpha = HEADER_SIZE + len(body)
        body += pack_rows(turn(planes, width, height, degrees), 1, alpha_stride)
    struct.pack_into("<HH", header, WIDTH_OFFSET, new_width, new_height)
    struct.pack_into("<II", header, STRIDE_OFFSET, new_stride, HEADER_SIZE)
    struct.pack_into("<II", header, ALPHA_STRIDE_OFFSET, alpha_stride, alpha)
    struct.pack_into("<I", header, FILE_SIZE_OFFSET, HEADER_SIZE + len(body))
    struct.pack_into("<I", header, UNPACKED_SIZE_OFFSET, len(body))
    return bytes(header) + bytes(body)


def main():
    args = sys.argv[1:]
    degrees = 0
    if len(args) >= 2 and args[0] == "--rotate":
        if args[1] not in ("0", "90", "180", "270"):
            print("dmvi_to_dmvir: --rotate takes 0, 90, 180 or 270", file=sys.stderr)
            return 2
        degrees = int(args[1])
        args = args[2:]
    if len(args) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    try:
        with open(args[0], "rb") as source:
            raw = rotate(to_raw(source.read()), degrees)
    except (OSError, ValueError, IndexError) as error:
        print(f"dmvi_to_dmvir: {args[0]}: {error}", file=sys.stderr)
        return 1
    with open(args[1], "wb") as target:
        target.write(raw)
    return 0


if __name__ == "__main__":
    sys.exit(main())
