#!/usr/bin/env python3
"""Reads the log of the selector (or of a firmware) from the USB-Serial/JTAG of an ESP32-S3.

    esp_console.py [--port /dev/ttyACM0] [--seconds 8] [--reset]

--reset resets the chip first (the RTS line of the USB-Serial/JTAG is the EN pin), so the log of the whole boot is seen: the
port is open before the chip starts. DTR (the IO0 pin, download mode) stays low all the time. Needs pyserial.
"""
import argparse
import sys
import time

import serial


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyACM0")
    ap.add_argument("--seconds", type=float, default=8.0, help="how long to read (0: until Ctrl-C)")
    ap.add_argument("--reset", action="store_true", help="reset the chip after opening the port")
    args = ap.parse_args()

    port = serial.Serial()
    port.port = args.port
    port.baudrate = 115200          # ignored by the USB-Serial/JTAG, the port wants one
    port.timeout = 0.1
    port.dtr = False                # applied when the port opens
    port.rts = False
    port.open()
    try:
        if args.reset:
            port.dtr = False
            port.rts = True         # EN low: the chip is in reset
            time.sleep(0.1)
            port.rts = False
        end = time.monotonic() + args.seconds if args.seconds > 0 else None
        while end is None or time.monotonic() < end:
            data = port.read(256)
            if data:
                sys.stdout.write(data.decode("utf-8", "replace").replace("\r\n", "\n"))
                sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    finally:
        port.close()


if __name__ == "__main__":
    main()
