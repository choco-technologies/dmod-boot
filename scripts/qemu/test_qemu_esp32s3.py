#!/usr/bin/env python3
"""Regression test of the Elecrow DIS08070H firmware in the Espressif QEMU (esp32s3 machine).

  test_qemu_esp32s3.py <qemu-install-dir> <images-dir>      (images: make-images.py)

Boots the selector + bank A, works in the shell on the console (the UART0 of QEMU on a TCP socket), formats /ext, writes a file, restarts
the machine (the flash image is kept) and reads the file back.
"""
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import os

PROMPT = re.compile(rb"esp32s3fn16r8@/> $")
ANSI = re.compile(rb"\x1b\[[0-9;]*m")
PORT = 5555
BOOT_TIMEOUT = 120


class Machine:
    def __init__(self, qemu, flash, efuse):
        self.cmd = [
            os.path.join(qemu, "bin", "qemu-system-xtensa"), "-L", os.path.join(qemu, "share", "qemu"),
            "-M", "esp32s3", "-display", "none", "-m", "8M",
            "-drive", f"file={flash},if=mtd,format=raw",
            "-drive", f"file={efuse},if=none,format=raw,id=efuse",
            "-global", "driver=nvram.esp32s3.efuse,property=drive,value=efuse",
            "-global", "driver=ssi_psram,property=is_octal,value=true",
            "-serial", f"tcp::{PORT},server=on,wait=off", "-monitor", "none",
        ]

    def __enter__(self):
        self.proc = subprocess.Popen(self.cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        for _ in range(100):
            try:
                self.sock = socket.create_connection(("127.0.0.1", PORT))
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("cannot connect to the serial of QEMU")
        self.sock.settimeout(0.2)
        self.log = b""
        self.wait_prompt(BOOT_TIMEOUT)
        return self

    def __exit__(self, *a):
        self.sock.close()
        self.proc.kill()
        self.proc.wait()

    def wait_prompt(self, timeout):
        end = time.time() + timeout
        out = b""
        while time.time() < end:
            try:
                d = self.sock.recv(4096)
            except socket.timeout:
                d = b""
            out += d
            if PROMPT.search(ANSI.sub(b"", out)):
                self.log += out
                return ANSI.sub(b"", out).decode("latin1")
        self.log += out
        raise TimeoutError("no prompt; the console says:\n" + ANSI.sub(b"", out).decode("latin1")[-2000:])

    def run(self, cmd, timeout=30):
        for ch in cmd + "\r":
            self.sock.send(ch.encode())
            time.sleep(0.005)
        return self.wait_prompt(timeout)


def check(cond, what, out=""):
    print(("PASS " if cond else "FAIL ") + what)
    if not cond:
        print(out)
        global failed
        failed = True


failed = False


def main():
    qemu, images = sys.argv[1], sys.argv[2]
    work = tempfile.mkdtemp()
    flash = os.path.join(work, "flash.bin")
    shutil.copy(os.path.join(images, "flash.bin"), flash)      # QEMU writes into it
    efuse = os.path.join(images, "efuse.bin")
    try:
        with Machine(qemu, flash, efuse) as m:
            check("esp32s3fn16r8@/>" in ANSI.sub(b"", m.log).decode("latin1"), "boots to the shell")
            out = m.run("ls /dev")
            for node in ("psram", "dmflashx", "dmuartx", "tty0"):
                check(node in out, f"/dev/{node} exists", out)
            out = m.run("ps")
            check("dmell" in out, "ps lists the shell", out)
            out = m.run("mklittlefs /dev/dmflashx/ext", 120)
            check("done" in out, "mklittlefs formats /ext", out)
        with Machine(qemu, flash, efuse) as m:
            m.run("write /ext/c.txt hello")
            out = m.run("cat /ext/c.txt")
            check("hello" in out, "the file written to /ext reads back", out)
        with Machine(qemu, flash, efuse) as m:
            out = m.run("cat /ext/c.txt")
            check("hello" in out, "the file in /ext survives the restart", out)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    sys.exit(1 if failed else 0)


main()
