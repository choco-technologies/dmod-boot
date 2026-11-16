#!/usr/bin/env python3
"""Check that a crash of an application is contained to its process.

Connects to the TCP terminal Renode attaches to the board's console UART, waits for the shell prompt and runs
`faulttest` (tests/faulttest, an application that crashes on purpose). For each kind of crash it checks that

- the crash is reported on the standard output the application was writing to - the console - naming the application
  and the kind of fault,
- the application does not go on running after it,
- the shell is back at its prompt and works,
- the application can be run again (its module was unloaded, and loads afresh).

A stack overflow is not among the crashes: it needs the MPU guard of the stack to be caught before it destroys the
memory below the stack, and the emulator does not model the access rights of the MPU that the guard is made of (see
tests/fault_mpu for the check of that part, which runs on an emulated MPU).

Usage: test_renode_fault.py [--host HOST] [--port PORT] [--timeout SECONDS]
"""
import argparse
import sys
import time

from test_renode_uart import Terminal, check, connect, wait_for_prompt

ALIVE = "faulttest: still alive"

# (argument of faulttest, text the report of the fault has to contain)
CRASHES = [
    ("undef", "faulttest: illegal instruction"),
    ("state", "faulttest: illegal instruction"),
]


def run_crash(term, kind, report):
    ok = check(term, f"faulttest {kind}",
               lambda out: any(report in line for line in out)
               and any("Process terminated" in line for line in out)
               and not any(ALIVE in line for line in out),
               f"'faulttest {kind}' is reported ('{report}') and does not go on")
    token = f"after-{kind}-{int(time.time())}"
    ok &= check(term, f"echo {token}", lambda out: token in out, f"the shell works after '{kind}'")
    ok &= check(term, "faulttest ok", lambda out: ALIVE in out, f"faulttest runs again after '{kind}'")
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3456)
    parser.add_argument("--timeout", type=float, default=90, help="seconds to wait for the shell prompt")
    args = parser.parse_args()

    deadline = time.monotonic() + args.timeout
    print(f"Connecting to the console UART terminal at {args.host}:{args.port}...")
    term = Terminal(connect(args.host, args.port, deadline))
    if not wait_for_prompt(term, deadline):
        print("✗ No shell prompt on the console UART")
        print(f"Received: {term.text()[-500:]!r}")
        return 1

    if not check(term, "faulttest ok", lambda out: ALIVE in out, "faulttest runs and returns"):
        return 1
    return 0 if all([run_crash(term, kind, report) for kind, report in CRASHES]) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (TimeoutError, ConnectionError) as error:
        print(f"✗ {error}")
        sys.exit(1)
