#!/usr/bin/env python3
"""Check the touch panel of the Renode machine: injected touches reach touchtest.

run_renode_tests.sh adds touchtest (dmft5336's test tool) to the firmware and
starts Renode with its monitor on a TCP port (DMBOOT_RENODE_MONITOR_PORT).
Touches are injected into the emulated FT5336 through the monitor
(MoveTo/Press/Release - screen coordinates, the platform swaps the axes like
the real panel does) while this script drives the shell on the console UART:

- `touchtest info`: the chip answers on I2C (FT5336 chip ID 0x51)
- `touchtest read` before, during and after touches: the driver reports the
  exact screen coordinates (so the axis swap is undone) and the release
- `touchtest watch`: touches made while it waits are reported as they happen

Usage: test_renode_touch.py [--port PORT] [--monitor-port PORT]
                            [--touchscreen NAME] [--timeout SECONDS]
"""
import argparse
import os
import re
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_renode_uart import Terminal, at_prompt, check, connect, wait_for_prompt  # noqa: E402

# Screen points to touch: corners and middle of the 480x272 LCD
POINTS = [(100, 50), (470, 260), (240, 136), (5, 266)]
WATCH_TIMEOUT = 60
TELNET_NEGOTIATION = re.compile(rb"\xff[\xfb-\xfe].")
ANSI_ESCAPE = re.compile(rb"\x1b\[[0-9;]*[A-Za-z]")


class Monitor:
    """Minimal client for the Renode monitor on a telnet port."""

    def __init__(self, sock):
        self.sock = sock
        self.sock.settimeout(0.3)
        self.drain(1.0)

    def drain(self, wait):
        data = b""
        end = time.monotonic() + wait
        while time.monotonic() < end:
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                break
            data += chunk
            end = max(end, time.monotonic() + 0.3)
        data = ANSI_ESCAPE.sub(b"", TELNET_NEGOTIATION.sub(b"", data))
        return data.replace(b"\r", b"").decode(errors="replace")

    def run(self, command):
        """Run a monitor command; the telnet line editor may swallow the start of a line, so retry."""
        for _ in range(4):
            self.sock.sendall(command.encode() + b"\n")
            reply = self.drain(1.5)
            if "No such command or device" not in reply and "error" not in reply.lower():
                return reply
        raise RuntimeError(f"monitor command failed: {command!r}: {reply!r}")


def point_line(x, y):
    return re.compile(rf"^touch: 1/1 id=\d+ x={x} y={y} (down|contact)$")


def check_touches(term, monitor, touchscreen):
    ok = True
    for i, (x, y) in enumerate(POINTS):
        monitor.run(f"{touchscreen} MoveTo {x} {y}")
        if i == 0:
            monitor.run(f"{touchscreen} Press")
        pattern = point_line(x, y)
        ok &= check(term, "touchtest read", lambda out: any(pattern.match(line.strip()) for line in out),
                    f"Touch at ({x}, {y}) reported at the same screen coordinates")
    monitor.run(f"{touchscreen} Release")
    ok &= check(term, "touchtest read", lambda out: any(line.strip() == "touch: released" for line in out), "Release reported")
    return ok


def check_watch(term, monitor, touchscreen):
    """Touches made while touchtest watch waits for them are reported in order."""
    command = f"touchtest watch 3 {WATCH_TIMEOUT * 1000}"
    term.send(command)
    if not term.read_until(lambda text: b"watching for" in text, time.monotonic() + 15):
        print(f"✗ touchtest watch did not start: {term.text()[-300:]!r}")
        return False

    monitor.run(f"{touchscreen} MoveTo 60 40")
    monitor.run(f"{touchscreen} Press")
    time.sleep(1)
    monitor.run(f"{touchscreen} MoveTo 420 250")
    time.sleep(1)
    monitor.run(f"{touchscreen} Release")

    deadline = time.monotonic() + WATCH_TIMEOUT
    if not term.read_until(lambda text: b"touch: released" in text and at_prompt(text), deadline):
        print(f"✗ touchtest watch: touches not reported: {term.text()[-500:]!r}")
        return False
    lines = [line.strip() for line in term.text().decode(errors="replace").replace("\r", "").split("\n")]
    events = [line for line in lines if line.startswith("touch:")]
    expected = [point_line(60, 40), point_line(420, 250), re.compile(r"^touch: released$")]
    if len(events) != 3 or not all(p.match(e) for p, e in zip(expected, events)):
        print(f"✗ touchtest watch reported {events!r}")
        return False
    print("✓ touchtest watch reports press, move and release as they happen")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3456, help="console UART terminal port")
    parser.add_argument("--monitor-port", type=int, default=3457, help="Renode monitor port")
    parser.add_argument("--touchscreen", default="sysbus.i2c3.touchscreen",
                        help="Renode peripheral of the touch panel")
    parser.add_argument("--timeout", type=float, default=90,
                        help="seconds to wait for the shell prompt")
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout

    print(f"Connecting to the console UART terminal at {args.host}:{args.port}...")
    term = Terminal(connect(args.host, args.port, deadline))
    if not wait_for_prompt(term, deadline):
        print("✗ No shell prompt on the console UART")
        return 1
    print(f"Connecting to the Renode monitor at {args.host}:{args.monitor_port}...")
    monitor = Monitor(connect(args.host, args.monitor_port, deadline))

    ok = check(term, "touchtest info", lambda out: any("chip id:" in l and "0x51" in l for l in out),
               "FT5336 answers on I2C (chip ID 0x51)")
    ok &= check(term, "touchtest read", lambda out: any(line.strip() == "touch: released" for line in out), "Nothing touches the panel")
    if ok:
        ok &= check_touches(term, monitor, args.touchscreen)
        ok &= check_watch(term, monitor, args.touchscreen)

    print("✓ Touch panel works" if ok else "✗ Touch panel test failed")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
