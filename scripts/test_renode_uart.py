#!/usr/bin/env python3
"""Check that the shell answers on the console UART of the Renode machine.

Connects to the TCP terminal Renode attaches to the board's console UART
(DMBOOT_RENODE_CONSOLE_UART / DMBOOT_RENODE_UART_PORT), waits for the shell
prompt, then runs `echo <token>` and expects the token back on its own line.

Usage: test_renode_uart.py [--host HOST] [--port PORT] [--timeout SECONDS]
"""
import argparse
import re
import socket
import sys
import time

ANSI_ESCAPE = re.compile(rb"\x1b\[[0-9;]*[A-Za-z]")
# dmell's prompt: "<hostname>@<cwd>> " at the end of the output
PROMPT = re.compile(rb"\S+@\S*> ?$")


def at_prompt(text):
    return PROMPT.search(text) is not None


def connect(host, port, deadline):
    """Connect to the Renode terminal, retrying until it accepts connections."""
    while True:
        try:
            return socket.create_connection((host, port), timeout=5)
        except OSError as error:
            if time.monotonic() > deadline:
                raise TimeoutError(f"cannot connect to {host}:{port}: {error}")
            time.sleep(1)


class Terminal:
    def __init__(self, sock):
        self.sock = sock
        self.sock.settimeout(0.5)
        self.received = b""

    def read_until(self, predicate, deadline):
        """Read into self.received until predicate(text) holds or the deadline passes."""
        while not predicate(self.text()):
            if time.monotonic() > deadline:
                return False
            try:
                data = self.sock.recv(4096)
            except socket.timeout:
                continue
            if not data:
                raise ConnectionError("terminal closed the connection")
            self.received += data
        return True

    def text(self):
        return ANSI_ESCAPE.sub(b"", self.received)

    def send(self, line):
        self.received = b""
        self.sock.sendall(line.encode() + b"\r")


def wait_for_prompt(term, deadline):
    """Press Enter until the shell prints a prompt - it may still be starting."""
    while time.monotonic() < deadline:
        term.send("")
        if term.read_until(at_prompt, min(deadline, time.monotonic() + 5)):
            return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3456)
    parser.add_argument("--timeout", type=float, default=90,
                        help="seconds to wait for the shell, in total")
    args = parser.parse_args()

    deadline = time.monotonic() + args.timeout
    print(f"Connecting to the console UART terminal at {args.host}:{args.port}...")
    term = Terminal(connect(args.host, args.port, deadline))

    if not wait_for_prompt(term, deadline):
        print("✗ No shell prompt on the console UART")
        print(f"Received: {term.text()[-500:]!r}")
        return 1
    print(f"✓ Shell prompt: {term.text().strip().splitlines()[-1].decode(errors='replace')!r}")

    token = f"uart-test-{int(time.time())}"
    term.send(f"echo {token}")
    answered = term.read_until(
        lambda text: re.search(rb"^" + token.encode() + rb"\r?$", text, re.MULTILINE) is not None
        and at_prompt(text),
        deadline)
    if not answered:
        print(f"✗ Shell did not answer 'echo {token}'")
        print(f"Received: {term.text()[-500:]!r}")
        return 1
    print(f"✓ Shell answered 'echo {token}' on the console UART")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (TimeoutError, ConnectionError) as error:
        print(f"✗ {error}")
        sys.exit(1)
