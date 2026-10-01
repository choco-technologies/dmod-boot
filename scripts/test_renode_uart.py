#!/usr/bin/env python3
"""Check that the shell works on the console UART of the Renode machine.

Connects to the TCP terminal Renode attaches to the board's console UART
(DMBOOT_RENODE_CONSOLE_UART / DMBOOT_RENODE_UART_PORT), waits for the shell
prompt, then runs a few commands and checks what they print:

- `echo <token>` prints the token back
- `ls /dev/null` finds the null device, which dmdevfs always provides
- `echo <token> > /test.txt` followed by `cat /test.txt` reads the token back
  from a file created on the root filesystem

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
# Time a single command may take to print its output and the next prompt
COMMAND_TIMEOUT = 15
TEST_FILE = "/test.txt"
# Log output can share the UART with the shell (stdlog is bound to the tty
# too), so commands are only checked for what they must print, or not print
ERROR_LINE = re.compile(r"error|fail|cannot|not found", re.IGNORECASE)


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

    def run(self, command):
        """Run a command and return its output lines (without the echo and the prompt), or None on timeout."""
        echo = command.encode() + b"\n"

        def after_echo(text):
            # A prompt still in flight from an earlier command may arrive
            # first - only what follows the shell echoing this command counts
            index = text.replace(b"\r", b"").find(echo)
            return None if index < 0 else text.replace(b"\r", b"")[index + len(echo):]

        self.send(command)
        if not self.read_until(lambda text: after_echo(text) is not None and at_prompt(after_echo(text)),
                               time.monotonic() + COMMAND_TIMEOUT):
            return None
        lines = after_echo(self.text()).decode(errors="replace").split("\n")
        # The last line is the new prompt
        return [line for line in lines[:-1] if line.strip()]


def wait_for_prompt(term, deadline):
    """Press Enter until the shell prints a prompt - it may still be starting."""
    while time.monotonic() < deadline:
        term.send("")
        if term.read_until(at_prompt, min(deadline, time.monotonic() + 5)):
            return True
    return False


def check(term, command, expect, description):
    """Run command and require expect(output_lines) to hold."""
    output = term.run(command)
    if output is None:
        print(f"✗ {description}: no prompt after '{command}'")
        print(f"Received: {term.text()[-500:]!r}")
        return False
    if not expect(output):
        print(f"✗ {description}: unexpected output of '{command}': {output!r}")
        return False
    print(f"✓ {description}")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3456)
    parser.add_argument("--timeout", type=float, default=90,
                        help="seconds to wait for the shell prompt")
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
    checks = [
        (f"echo {token}", lambda out: token in out,
         "echo prints its argument"),
        ("ls /dev/null", lambda out: any("null" in line.split() for line in out),
         "ls /dev/null finds the null device"),
        (f"echo {token} > {TEST_FILE}", lambda out: not any(ERROR_LINE.search(line) for line in out),
         f"echo writes {TEST_FILE}"),
        (f"cat {TEST_FILE}", lambda out: token in out,
         f"cat reads {TEST_FILE} back"),
    ]
    for command, expect, description in checks:
        if not check(term, command, expect, description):
            return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (TimeoutError, ConnectionError) as error:
        print(f"✗ {error}")
        sys.exit(1)
