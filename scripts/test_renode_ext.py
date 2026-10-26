#!/usr/bin/env python3
"""Test littlefs on the emulated N25Q128A through the firmware shell.

/ext is filled by run_renode_tests.sh (format and upload-ext, like install-all)
before this runs, so nothing is formatted here: the test writes a file, reads
it back. (The unmount and mount are in run_renode_tests.sh step 4b; unmounting
a /ext whose units are running stops them, that takes long and is not a QSPI test.)
"""
import argparse
import socket
import sys
import time
from test_renode_uart import Terminal, connect, wait_for_prompt, ERROR_LINE


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=3456)
    parser.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout
    with connect('127.0.0.1', args.port, deadline) as sock:
        term = Terminal(sock)
        if not wait_for_prompt(term, deadline):
            raise RuntimeError('no UART shell prompt')

        def run(command, expect=None):
            result = term.run(command)
            if result is None or any(ERROR_LINE.search(line) for line in result):
                raise RuntimeError(f'{command}: {result!r}')
            if expect is not None and not any(expect in line for line in result):
                raise RuntimeError(f'{command}: missing {expect!r}: {result!r}')
            return result

        run('ls /dev/dmspiflashx/flash', 'flash')
        run('ls /ext/bin', 'cat.dmfc')            # (the modules sent in step 4b)
        token = f'qspi-littlefs-{time.time_ns()}'
        run(f'echo {token} > /ext/qspi-test.txt')
        run('cat /ext/qspi-test.txt', token)
        print('PASS QUADSPI: /ext/bin is there (sent in step 4b, after a remount); write and read littlefs')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, socket.timeout) as error:
        print(f'FAIL QUADSPI: {error}', file=sys.stderr)
        sys.exit(1)
