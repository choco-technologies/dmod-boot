#!/usr/bin/env python3
"""Send files to a dmod-boot device over its UART console (YMODEM batch).

The device's dmell receives them with its `ymodem` command: this script
types `ymodem recv -d DEST` into the console, waits for the receiver's
'C' and sends every file - its name (with directories) under DEST:

    ymodem_send.py build/sdcard                         (the card's root)
    ymodem_send.py --dest views view.dmv fonts/         (views/ on the card)
    ymodem_send.py --dest /mnt/sd local/dir=remote/dir  (that directory)

A DEST that is not absolute is on the SD card: the card is found on the
device - `ls /mnt`, where automount mounts every card (/mnt/<label>, or
/mnt/<node name>) - when it has one; --card NAME picks one of several,
--card none sends under the shell's current directory instead.

Shell commands can be run first (--run, "-" before one lets it fail) - e.g. to create and mount
a file system the files then go to - and --ensure-dir DIR fails unless DIR is there on the device:

    ymodem_send.py --run "-umount /ext" --run "mklittlefs /dev/dmspiflashx/flash" --run "mount ... /ext"

A FILE is sent by its name, a DIR with everything in it (names relative
to it), SRC=NAME as NAME (a directory: under NAME). Only the standard
library (termios): no pyserial needed.
"""

import argparse
import fcntl
import os
import re
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


def other_users(port):
    """(pid, program) of the other processes that have `port` open - a terminal program on it would take the
    answers and type into the shell with the script"""
    users = []
    try:
        target = os.path.realpath(port)
        for pid in os.listdir('/proc'):
            if not pid.isdigit() or int(pid) == os.getpid():
                continue
            try:
                for fd in os.listdir(f'/proc/{pid}/fd'):
                    if os.path.realpath(f'/proc/{pid}/fd/{fd}') == target:
                        with open(f'/proc/{pid}/comm') as f:
                            users.append((int(pid), f.read().strip()))
                        break
            except OSError:
                continue
    except OSError:
        pass
    return users


class Link:
    """Bytes in and out: a serial port, or stdin / stdout (--stdio, tests)"""

    retries = 0

    def __init__(self, port, baud):
        if port is None:
            self.rfd, self.wfd, self.saved = sys.stdin.fileno(), sys.stdout.fileno(), None
            return
        users = other_users(port)
        if users:
            raise Failure(f'{port} is open in {", ".join(f"{name} (pid {pid})" for pid, name in users)}: close it '
                          '(two programs on one console take each other\'s answers)')
        fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
        try:
            fcntl.ioctl(fd, termios.TIOCEXCL)          # (no other program can open it meanwhile)
        except OSError:
            pass
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

    def drain(self, quiet=0.2, limit=3.0):
        """What the device says until it is quiet (at most `limit` seconds: a log that never stops)"""
        out = bytearray()
        until = time.monotonic() + limit
        try:
            while time.monotonic() < until and (b := self.read(quiet)) is not None:
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
    wait_for(link, (CRC,), 45.0, f'{name}: next')
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


PROMPT = re.compile(r'@\S*>')


def clean(data):
    return re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', data.decode(errors='replace')).replace('\r', '')


def run_command(link, command, timeout):
    """Type a shell command, return what the console said until the shell was back at its prompt.

    The console is shared with the log: other threads' lines run into the echo and into the output, so the
    command's echo is not looked for - the shell prints one prompt when it is done (the prompts the Enter
    before it printed are drained first)."""
    link.write(b'\r')
    link.drain(0.5)
    link.write(command.encode() + b'\r')
    end = time.monotonic() + timeout
    seen = bytearray()
    while time.monotonic() < end:
        b = link.read(0.6)
        if b is not None:
            seen.append(b)
        if PROMPT.search(clean(seen)):
            seen += link.drain(0.3)     # (the prompt is back: the rest of the output; a log that never stops is no reason to wait)
            return clean(seen)
    raise Failure(f'"{command}" did not finish in {timeout:.0f} s')


def wait_shell(link, wait):
    """The shell answers: a prompt comes back to Enter - looked for again for `wait` seconds (the device is starting)"""
    until = time.monotonic() + wait
    while True:
        link.write(b'\r')
        if PROMPT.search(clean(link.drain(0.8))):
            return
        if time.monotonic() >= until:
            raise Failure('the shell does not answer (is the console on this port?)')


def failed(command, said):
    """The command's own error message: 'mount: [ERROR] ...' / 'DEVICE: cannot ...' (log lines of others are not it)"""
    name = command.split()[0]
    return re.search(rf'{re.escape(name)}: \[ERROR\]|: cannot ', said) is not None


def run_commands(link, commands, timeout, log):
    for command in commands:
        tolerant = command.startswith('-')
        command = command.lstrip('-').strip()
        log(f'  $ {command}')
        said = run_command(link, command, timeout)
        errors = [line.strip() for line in said.splitlines() if failed(command, line)]
        for line in errors:
            log(f'    {line}')
        if errors and not tolerant:
            raise Failure(f'"{command}" failed')


def ensure_dir(link, path, timeout):
    said = run_command(link, f'ls {path}', timeout)
    if re.search(r"Cannot access '" + re.escape(path), said) or 'No such file' in said:
        raise Failure(f'{path} is not there on the device (not mounted? run format-ext on a new chip)')


def mounted_cards(link):
    """What /mnt holds on the device - the cards automount mounted"""
    link.write(b'\r')
    link.drain()
    link.write(b'ls /mnt\r')
    said = link.drain(0.5).decode(errors='replace')
    said = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', said)
    if 'ls /mnt' not in said or 'ERROR' in said:
        return []                       # (the shell not answering yet - starting -, or no /mnt)
    said = said.split('ls /mnt', 1)[1]                      # (what the echo is followed by - it may run into it)
    said = re.sub(r'\S*@\S*>', '', said)                   # (the prompts)
    names = []
    for line in said.replace('\r', '\n').split('\n'):
        names += [n for n in re.split(r'\s{2,}', line.strip()) if n]
    return [n for n in names if re.fullmatch(r'[\x21-\x7e][\x20-\x7e]*', n)]   # (not what the line had before)


def find_card(link, card, wait, log):
    """The card's directory: CARD, or the one card mounted - looked for again for `wait` seconds"""
    until = time.monotonic() + wait
    while True:
        cards = mounted_cards(link)
        if card != 'auto' and card in cards:
            return f'/mnt/{card}'
        if card == 'auto' and len(cards) == 1:
            return f'/mnt/{cards[0]}'
        if card == 'auto' and len(cards) > 1:
            raise Failure(f'more than one card on the device ({", ".join(cards)}): pick one with --card, '
                          'or give an absolute --dest')
        if time.monotonic() >= until:
            what = f'no card {card} in /mnt' if card != 'auto' else 'no card mounted in /mnt'
            raise Failure(f'{what} (found: {", ".join(cards) or "nothing"}) - is the card in, formatted (FAT)?')
        log('  waiting for the card ...')
        time.sleep(2.0)


def destination(link, args, log):
    """Where the files go: --dest as it is (absolute), or under the card"""
    if args.dest.startswith('/') or args.card == 'none':
        return args.dest
    root = find_card(link, args.card, args.wait, log)
    dest = f'{root}/{args.dest.strip("/")}' if args.dest.strip('/') else root
    log(f'  to {dest}')
    return dest


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
    ap.add_argument('sources', nargs='*', help='FILE, DIR or SRC=NAME')
    ap.add_argument('--run', action='append', default=[], metavar='COMMAND',
                    help='a shell command to run first (repeatable); a leading "-" lets it fail')
    ap.add_argument('--ensure-dir', metavar='DIR', help='fail unless DIR exists on the device (it is listed)')
    ap.add_argument('--timeout', type=float, default=60.0, metavar='SECONDS', help='a --run command may take this long')
    ap.add_argument('--port', default='/dev/ttyACM0', help='the device console (default /dev/ttyACM0)')
    ap.add_argument('--baud', type=int, default=921600)
    ap.add_argument('--dest', default='', help='the directory on the device the names are under: absolute, '
                    'or on the SD card (default: the card\'s root)')
    ap.add_argument('--card', default='auto', metavar='NAME',
                    help='the card a relative --dest is on: its name in /mnt (auto: the one there is; none: '
                    'under the shell\'s current directory)')
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

    try:
        link = Link(None if args.stdio else args.port, args.baud)
    except Failure as e:
        print(f'ymodem_send: {e}', file=sys.stderr)
        return 1
    transferring = False
    try:
        if args.run or args.ensure_dir:
            wait_shell(link, args.wait)
            run_commands(link, args.run, args.timeout, log)
            if args.ensure_dir:
                ensure_dir(link, args.ensure_dir, args.timeout)
        if not files:
            return 0
        if args.no_command:
            wait_for(link, (CRC,), 15.0, 'the receiver')
        else:
            dest = destination(link, args, log)
            command = f'ymodem recv -d {dest}' if dest else 'ymodem recv'
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
        transferring = True
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
            if transferring:
                link.write(bytes([CAN] * 4))     # (not into the shell: it would take them for commands)
        except OSError:
            pass
        print(f'ymodem_send: {e}', file=sys.stderr)
        return 1
    finally:
        link.close()


if __name__ == '__main__':
    sys.exit(main())
