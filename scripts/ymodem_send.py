#!/usr/bin/env python3
"""Send files to a dmod-boot device over its UART console (YMODEM batch).

The device's dmell receives them with its `ymodem` command: this script
types `ymodem recv -d DEST` into the console, waits for the receiver's
'C' and sends every file - its name (with directories) under DEST:

    ymodem_send.py --port /dev/ttyACM0 --dest /mnt/dmsdio0_0p1 build/sdcard
    ymodem_send.py --dest /mnt/dmsdio0_0p1/views view.dmv fonts/
    ymodem_send.py --dest /mnt/sd local/dir=remote/dir

A FILE is sent by its name, a DIR with everything in it (names relative
to it), SRC=NAME as NAME (a directory: under NAME). Only the standard
library (termios): no pyserial needed.
"""

import argparse
import os
import select
import sys
import termios
import time
import tty

SOH, STX, EOT, ACK, NAK, CAN, CRC = 0x01, 0x02, 0x04, 0x06, 0x15, 0x18, ord('C')
BAUDS = {
    9600: termios.B9600, 19200: termios.B19200, 38400: termios.B38400, 57600: termios.B57600,
    115200: termios.B115200, 230400: termios.B230400, 460800: getattr(termios, 'B460800', None),
    921600: getattr(termios, 'B921600', None),
}


class Failure(Exception):
    pass


class Link:
    """Bytes in and out: a serial port, or stdin / stdout (--stdio, tests)"""

    retries = 0

    def __init__(self, port, baud):
        if port is None:
            self.rfd, self.wfd, self.saved = sys.stdin.fileno(), sys.stdout.fileno(), None
            return
        fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
        self.saved = termios.tcgetattr(fd)
        tty.setraw(fd)
        attrs = termios.tcgetattr(fd)
        speed = BAUDS.get(baud)
        if speed is None:
            raise Failure(f'unsupported baud rate {baud}')
        attrs[4] = attrs[5] = speed
        attrs[2] = (attrs[2] & ~termios.CRTSCTS) | termios.CLOCAL | termios.CREAD
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIOFLUSH)
        self.rfd = self.wfd = fd

    def close(self):
        if self.saved is not None:
            termios.tcsetattr(self.rfd, termios.TCSADRAIN, self.saved)
            os.close(self.rfd)

    def write(self, data):
        view = memoryview(data)
        while view:
            n = os.write(self.wfd, view)
            view = view[n:]

    def read(self, timeout):
        """One byte, None after `timeout` seconds"""
        ready, _, _ = select.select([self.rfd], [], [], timeout)
        if not ready:
            return None
        b = os.read(self.rfd, 1)
        if not b:
            raise Failure('the device closed the connection')
        return b[0]

    def drain(self, quiet=0.2):
        """What the device says until it is quiet"""
        out = bytearray()
        try:
            while (b := self.read(quiet)) is not None:
                out.append(b)
        except Failure:
            pass                        # (closed: what it said is all)
        return bytes(out)


def crc16(data):
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


def packet(number, data, size):
    data = data.ljust(size, b'\x1a' if number else b'\x00')
    c = crc16(data)
    return bytes([SOH if size == 128 else STX, number & 0xFF, 0xFF - (number & 0xFF)]) + data + bytes([c >> 8, c & 0xFF])


def wait_for(link, wanted, timeout, what):
    """One of `wanted` (bytes) - others skipped; CAN CAN: the device gave up"""
    end = time.monotonic() + timeout
    cans = 0
    while time.monotonic() < end:
        b = link.read(max(0.0, end - time.monotonic()))
        if b is None:
            break
        if b == CAN:
            cans += 1
            if cans >= 2:
                raise Failure(f'the device cancelled ({what})')
            continue
        cans = 0
        if b in wanted:
            return b
    raise Failure(f'no answer from the device ({what})')


def send_packet(link, number, data, size, what, retries=10):
    p = packet(number, data, size)
    for attempt in range(retries):
        if attempt > 0:
            link.retries += 1
        link.write(p)
        try:
            if wait_for(link, (ACK, NAK), 3.0, what) == ACK:
                return
        except Failure as e:
            if 'cancelled' in str(e):
                raise
    raise Failure(f'{what}: not acknowledged')


def send_file(link, path, name, block, progress):
    size = os.path.getsize(path)
    header = name.encode() + b'\x00' + str(size).encode() + b'\x00'
    if len(header) > 128:
        raise Failure(f'{name}: name too long for YMODEM')
    send_packet(link, 0, header, 128, f'{name}: header')
    wait_for(link, (CRC,), 10.0, f'{name}: data')
    sent, number = 0, 1
    with open(path, 'rb') as f:
        while chunk := f.read(block):
            send_packet(link, number, chunk, 128 if len(chunk) <= 128 else block, f'{name}: block {number}')
            number += 1
            sent += len(chunk)
            progress(name, sent, size)
    for attempt in range(10):
        link.write(bytes([EOT]))
        if wait_for(link, (ACK, NAK), 3.0, f'{name}: end') == ACK:
            break
    wait_for(link, (CRC,), 10.0, f'{name}: next')
    return size


def receiver_ready(link, command, timeout):
    """The command's echo, then the receiver's 'C' - twice in a row (it sends one a second): not a 'C' of a log"""
    end = time.monotonic() + timeout
    seen, last = bytearray(), None
    while time.monotonic() < end:
        b = link.read(max(0.0, end - time.monotonic()))
        if b is None:
            return False
        if command not in seen:
            seen.append(b)
            if len(seen) > 4096:
                del seen[:2048]
            continue
        if b == CRC and last == CRC:
            return True
        last = b
    return False


def files_of(sources):
    """(local path, name sent) of every source"""
    out = []
    for source in sources:
        local, _, name = source.partition('=')
        if os.path.isdir(local):
            for root, dirs, names in os.walk(local):
                dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
                for n in sorted(names):
                    if n.startswith('.'):
                        continue                # (.download_complete, ...)
                    full = os.path.join(root, n)
                    rel = os.path.relpath(full, local).replace(os.sep, '/')
                    out.append((full, f'{name.rstrip("/")}/{rel}' if name else rel))
        elif os.path.isfile(local):
            out.append((local, name or os.path.basename(local)))
        else:
            raise Failure(f'{local}: no such file or directory')
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('sources', nargs='+', help='FILE, DIR or SRC=NAME')
    ap.add_argument('--port', default='/dev/ttyACM0', help='the device console (default /dev/ttyACM0)')
    ap.add_argument('--baud', type=int, default=921600)
    ap.add_argument('--dest', default='', help='the directory on the device the names are under')
    ap.add_argument("--block", type=int, choices=(128, 1024), default=1024,
                    help='YMODEM block size (default 1024)')
    ap.add_argument('--no-command', action='store_true', help='ymodem recv is already running')
    ap.add_argument('--wait', type=float, default=0.0, metavar='SECONDS',
                    help='the device may still be starting: type the command again until it answers (after a flash)')
    ap.add_argument('--stdio', action='store_true', help='stdin / stdout instead of a port (tests)')
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    files = files_of(args.sources)
    log = (lambda *a: None) if args.quiet else (lambda *a: print(*a, file=sys.stderr, flush=True))

    def progress(name, sent, size):
        if not args.quiet:
            print(f'\r  {name}: {sent * 100 // max(size, 1)}%', end='', file=sys.stderr, flush=True)

    link = Link(None if args.stdio else args.port, args.baud)
    try:
        if args.no_command:
            wait_for(link, (CRC,), 15.0, 'the receiver')
        else:
            command = f'ymodem recv -d {args.dest}' if args.dest else 'ymodem recv'
            until = time.monotonic() + args.wait
            while True:
                link.write(b'\r')
                link.drain()
                link.write(command.encode() + b'\r')
                if receiver_ready(link, command.encode(), 8.0):
                    break
                if time.monotonic() >= until:
                    raise Failure('no ymodem receiver answered (is the console on this port, ymodem installed?)')
                log('  waiting for the device ...')
        start, total = time.monotonic(), 0
        for path, name in files:
            total += send_file(link, path, name, args.block, progress)
            log(f'\r  {name}: {os.path.getsize(path)} bytes')
        send_packet(link, 0, b'', 128, 'the end of the batch')
        seconds = max(time.monotonic() - start, 0.001)
        said = link.drain(0.5).decode(errors='replace').strip()
        log(f'{len(files)} file(s), {total} bytes in {seconds:.1f} s ({total / seconds / 1024:.1f} KiB/s)'
            + (f', {link.retries} block(s) sent again' if link.retries else ''))
        if said:
            log(f'device: {said.splitlines()[0] if said.startswith("ymodem") else said}')
        return 0
    except Failure as e:
        try:
            link.write(bytes([CAN] * 4))
        except OSError:
            pass
        print(f'ymodem_send: {e}', file=sys.stderr)
        return 1
    finally:
        link.close()


if __name__ == '__main__':
    sys.exit(main())
