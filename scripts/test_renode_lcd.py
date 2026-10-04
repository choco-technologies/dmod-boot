#!/usr/bin/env python3
"""Check the LCD of the Renode machine: what lcdtest draws is what the display shows.

run_renode_tests.sh adds lcdtest (dmlcdtft's test tool) to the firmware and
has Renode write every frame the LCD controller renders to a file
(DMBOOT_RENODE_LCD_CAPTURE). Driving the shell on the console UART, this
script checks:

- the splash screen (with --splash-logo): before anything is drawn, the
  display shows the splash logo in the middle of a screen of SPLASH_COLOR
  (the clear_color of dmlcdtft's lcd.ini for the board)
- `lcdtest info`: the display's geometry and pixel format
- `lcdtest selftest`: drawing and reading back the framebuffer
- `lcdtest fill`, `bars` and `gradient` (the last one drawn through write()):
  the frame the controller renders matches the picture, pixel by pixel, so
  the layer's address, size, stride, pixel format and channel order are
  right

The expected pictures mirror dmlcdtft's tools/lcdtest. A frame matches when
every channel of every pixel is within TOLERANCE of the 24-bit color drawn -
the display stores RGB565, which loses the low bits.

Usage: test_renode_lcd.py --frame-file FILE [--splash-logo DMVIR] [--port PORT] [--timeout SECONDS]
"""
import argparse
import os
import re
import struct
import sys
import time
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_renode_uart import Terminal, check, connect, wait_for_prompt  # noqa: E402

WIDTH = 480
HEIGHT = 272
PIXEL_FORMAT = "rgb565"
# RGB565 keeps 5/6 bits a channel: up to 7 levels lost by truncation
TOLERANCE = 8
# Background of the splash screen - clear_color in dmlcdtft's lcd.ini
SPLASH_COLOR = (0x04, 0x14, 0x31)
# Time the emulated display takes to show a new picture (it repaints at a
# fixed rate) and the capture to reach the file
FRAME_TIMEOUT = 15


def fill_picture(color):
    return lambda x, y: color


def bars_picture(x, y):
    """lcdtest bars: 8 color bars on the top 2/3, a 16-step gray ramp below, a 2 pixel white frame."""
    if x < 2 or y < 2 or x >= WIDTH - 2 or y >= HEIGHT - 2:
        return (255, 255, 255)
    bars_height = HEIGHT * 2 // 3
    if y < bars_height:
        colors = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
                  (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
        return colors[next(i for i in range(8) if x < (i + 1) * WIDTH // 8)]
    level = next(i for i in range(16) if x < (i + 1) * WIDTH // 16) * 255 // 15
    return (level, level, level)


def gradient_picture(x, y):
    """lcdtest gradient: red grows left to right, green top to bottom, blue the other way than red."""
    red = x * 255 // (WIDTH - 1)
    return (red, y * 255 // (HEIGHT - 1), 255 - red)


def splash_picture(path):
    """The splash screen: the logo of a .dmvir (RGB565A8) blended over SPLASH_COLOR, in the middle."""
    with open(path, "rb") as logo:
        data = logo.read()
    if data[:4] != b"DMVI" or data[16] != 3:
        raise ValueError(f"{path} is not an RGB565A8 .dmvir")
    width, height = struct.unpack_from("<HH", data, 12)
    stride, pixels, alpha_stride, alpha = struct.unpack_from("<IIII", data, 20)
    left, top = (WIDTH - width) // 2, (HEIGHT - height) // 2

    def picture(x, y):
        lx, ly = x - left, y - top
        if not (0 <= lx < width and 0 <= ly < height):
            return SPLASH_COLOR
        value, = struct.unpack_from("<H", data, pixels + ly * stride + 2 * lx)
        a = data[alpha + ly * alpha_stride + lx]
        color = ((value >> 11) * 255 // 31, ((value >> 5) & 63) * 255 // 63, (value & 31) * 255 // 31)
        return tuple((c * a + b * (255 - a) + 127) // 255 for c, b in zip(color, SPLASH_COLOR))
    return picture


def decode_frame(data):
    """Parse a capture file (see configs/renode/lcd_capture.py.in) into (width, height, rows of RGB)."""
    header, _, pixels = data.partition(b"\n")
    match = re.fullmatch(rb"DMLCD (\d+) (\d+) ([A-Z]+)(\d+) (\w+)", header)
    if match is None:
        raise ValueError(f"unknown frame header {header[:64]!r}")
    width, height = int(match.group(1)), int(match.group(2))
    channels = match.group(3).decode()
    digits = match.group(4).decode()
    # RGB565 -> 5,6,5 bits; RGBX8888 -> 8 each
    bits = [int(d) for d in digits] if len(digits) == len(channels) else [int(digits) // len(channels)] * len(channels)
    bytes_per_pixel = sum(bits) // 8
    if len(pixels) < width * height * bytes_per_pixel:
        raise ValueError("frame shorter than its header says")
    order = "little" if match.group(5) == b"LittleEndian" else "big"
    shifts = {}
    shift = sum(bits)
    for name, size in zip(channels, bits):
        shift -= size
        shifts[name] = (shift, (1 << size) - 1)

    def channel(value, name):
        offset, mask = shifts[name]
        return ((value >> offset) & mask) * 255 // mask

    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            start = (y * width + x) * bytes_per_pixel
            value = int.from_bytes(pixels[start:start + bytes_per_pixel], order)
            row.append((channel(value, "R"), channel(value, "G"), channel(value, "B")))
        rows.append(row)
    return width, height, rows


def mismatches(frame, picture):
    width, height, rows = frame
    if (width, height) != (WIDTH, HEIGHT):
        return [f"frame is {width}x{height}, expected {WIDTH}x{HEIGHT}"]
    found = []
    for y in range(height):
        for x in range(width):
            expected = picture(x, y)
            actual = rows[y][x]
            if any(abs(a - e) > TOLERANCE for a, e in zip(actual, expected)):
                found.append(f"({x},{y}) is {actual}, expected {expected}")
    return found


def write_png(path, frame):
    width, height, rows = frame
    raw = b"".join(b"\0" + bytes(c for pixel in row for c in pixel) for row in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    with open(path, "wb") as png:
        png.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                  + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def read_frame(path):
    try:
        with open(path, "rb") as capture:
            return decode_frame(capture.read())
    except FileNotFoundError:
        return None


def wait_for_picture(path, picture, description):
    """Wait until the captured frame shows picture; on timeout, describe and save the last frame."""
    deadline = time.monotonic() + FRAME_TIMEOUT
    frame = None
    while True:
        frame = read_frame(path) or frame
        found = mismatches(frame, picture) if frame is not None else ["no frame was captured"]
        if not found:
            print(f"✓ {description}")
            return True
        if time.monotonic() > deadline:
            break
        time.sleep(0.5)
    print(f"✗ {description}: {len(found)} pixels differ, e.g. {'; '.join(found[:3])}")
    if frame is not None:
        saved = os.path.splitext(path)[0] + "_failed.png"
        write_png(saved, frame)
        print(f"  last frame saved to {saved}")
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--frame-file", required=True, help="DMBOOT_RENODE_LCD_CAPTURE of the build")
    parser.add_argument("--splash-logo", help="the .dmvir of the splash logo (build/eviews/splash_logo.dmvir)")
    parser.add_argument("--port", type=int, default=3456)
    parser.add_argument("--timeout", type=float, default=60, help="seconds to wait for the shell")
    args = parser.parse_args()

    term = Terminal(connect("127.0.0.1", args.port, time.monotonic() + args.timeout))
    if not wait_for_prompt(term, time.monotonic() + args.timeout):
        print("✗ No shell prompt on the console UART")
        return 1

    # Nothing has drawn on the display yet: it still shows the splash screen
    if args.splash_logo and not wait_for_picture(args.frame_file, splash_picture(args.splash_logo),
                                                 "the display shows the splash screen"):
        return 1

    info = [f"resolution:   {WIDTH}x{HEIGHT}", f"pixel format: {PIXEL_FORMAT}"]
    if not check(term, "lcdtest info", lambda out: all(any(i in line for line in out) for i in info),
                 f"lcdtest info: {WIDTH}x{HEIGHT} {PIXEL_FORMAT}"):
        return 1
    if not check(term, "lcdtest selftest", lambda out: "lcdtest: selftest PASSED" in out,
                 "lcdtest selftest reads back what it drew"):
        return 1

    pictures = [
        ("lcdtest fill 0xFFFF0000", fill_picture((255, 0, 0)), "the display shows a red fill"),
        ("lcdtest fill 0xFF0000FF", fill_picture((0, 0, 255)), "the display shows a blue fill"),
        ("lcdtest bars", bars_picture, "the display shows the color bars"),
        ("lcdtest gradient", gradient_picture, "the display shows the gradient drawn through write()"),
    ]
    for command, picture, description in pictures:
        output = term.run(command)
        if output is None or any("error" in line.lower() for line in output):
            print(f"✗ {description}: '{command}' failed: {output!r}")
            return 1
        if not wait_for_picture(args.frame_file, picture, description):
            return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (TimeoutError, ConnectionError, ValueError) as error:
        print(f"✗ {error}")
        sys.exit(1)
