#!/usr/bin/env python3
"""Talk to the console of a board on a serial port: wait for the prompt, send commands, print the answers.

For the boards whose console is a USB serial port (dmusbserial: the ESP32-S3 USB Serial/JTAG, /dev/ttyACM*).

Opening such a port RESETS the board (the reset of the USB Serial/JTAG follows DTR / RTS, also when they are set low before the
open), so the script opens the port, waits for the boot to reach the prompt and only then sends the commands. Anything sent
earlier is lost or makes the write time out.

    scripts/serial_console.py --port /dev/ttyACM1 "ls /" "echo hello"
    scripts/serial_console.py --port /dev/ttyACM1 --no-reset-wait "uptime"      # the board is up already (port kept open elsewhere)

Needs pyserial (pip install pyserial).
"""
import argparse
import re
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial is needed: pip install pyserial")


def drain(port, seconds, until=None):
    """Reads for up to `seconds`, earlier when the regular expression `until` matches what has been read."""
    end = time.time() + seconds
    data = b""
    pattern = re.compile(until) if until else None
    while time.time() < end:
        data += port.read(4096)
        if pattern and pattern.search(data.decode("latin1")):
            break
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("commands", nargs="*", help="lines to send, one after another")
    parser.add_argument("--port", default="/dev/ttyACM1", help="serial port (default: %(default)s)")
    parser.add_argument("--baud", type=int, default=115200, help="baud rate (a USB port ignores it; default: %(default)s)")
    parser.add_argument("--prompt", default=r"\x1b\[0m> ?$|@\S*\x1b\[0m> ?$|/> ?$",
                        help="regular expression of the prompt that ends the wait for the boot and for each answer")
    parser.add_argument("--boot-wait", type=float, default=90.0, help="seconds to wait for the first prompt (default: %(default)s)")
    parser.add_argument("--answer-wait", type=float, default=3.0, help="seconds to wait for the answer to a command (default: %(default)s)")
    parser.add_argument("--no-reset-wait", action="store_true", help="do not wait for the boot (the board is running already)")
    parser.add_argument("--raw", action="store_true", help="keep the ANSI colour codes")
    args = parser.parse_args()

    port = serial.Serial()
    port.port = args.port
    port.baudrate = args.baud
    port.timeout = 0.2
    port.write_timeout = 3
    port.dtr = False
    port.rts = False
    port.open()

    def show(data):
        text = data.decode("latin1")
        if not args.raw:
            text = re.sub(r"\x1b\[[0-9;]*m", "", text)
        sys.stdout.write(text.replace("\r", ""))
        sys.stdout.flush()

    if not args.no_reset_wait:
        show(drain(port, args.boot_wait, args.prompt))
    drain(port, 0.5)
    for command in args.commands:
        try:
            port.write(command.encode() + b"\r")
        except serial.SerialTimeoutException:
            sys.exit("\nwrite timed out: nothing reads the port (the board is not at the prompt)")
        show(drain(port, args.answer_wait, args.prompt))
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
