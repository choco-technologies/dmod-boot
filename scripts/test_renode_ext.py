#!/usr/bin/env python3
"""Format a fresh emulated N25Q128A and test littlefs through the firmware shell.

Use only with a disposable Renode instance. --format is required explicitly;
this destroys the contents of /dev/dmspiflashx/flash in that instance.
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
    parser.add_argument('--format', action='store_true', required=True,
                        help='erase the disposable emulator flash and create littlefs')
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
        run('mklittlefs /dev/dmspiflashx/flash')
        run('mount -t dmlittlefs -o device=/dev/dmspiflashx/flash /ext')
        token = f'qspi-littlefs-{time.time_ns()}'
        run(f'echo {token} > /ext/qspi-test.txt')
        run('cat /ext/qspi-test.txt', token)
        run('umount /ext')
        run('mount -t dmlittlefs -o device=/dev/dmspiflashx/flash /ext')
        run('cat /ext/qspi-test.txt', token)
        print('PASS QUADSPI: format, mount, write, read and remount littlefs')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, socket.timeout) as error:
        print(f'FAIL QUADSPI: {error}', file=sys.stderr)
        sys.exit(1)
