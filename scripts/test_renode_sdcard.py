#!/usr/bin/env python3
"""Check the SD card of the Renode machine through the shell on the console UART.

run_renode_tests.sh inserts the image make_sdcard_image.py builds - an MBR
with one FAT16 partition labelled LABEL - in the board's card slot
(DMBOOT_RENODE_SDCARD). This script checks, driving the shell:

- the card is identified: dmdevfs shows the medium and its partition
- automount mounted the partition at /mnt/<LABEL>
- a file of the image reads back as the image holds it
- a file written to the card reads back after the card was unmounted and
  mounted again, i.e. from the card itself rather than a cache

Usage: test_renode_sdcard.py [--port PORT] [--device NODE] [--timeout SECONDS]
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_sdcard_image import FILES, LABEL  # noqa: E402
from test_renode_uart import ERROR_LINE, Terminal, check, connect, wait_for_prompt  # noqa: E402

MOUNT_POINT = f"/mnt/{LABEL}"
REMOUNT_POINT = "/mnt/sdcheck"
WRITE_FILE = "WRITE.TXT"


def no_errors(out):
    return not any(ERROR_LINE.search(line) for line in out)


def wait_for_automount(term, deadline):
    """Poll `ls /mnt` until automount mounted the card - identification runs in the background."""
    while time.monotonic() < deadline:
        output = term.run("ls /mnt")
        if output is not None and any(LABEL in line.split() for line in output):
            return True
        time.sleep(2)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=3456)
    parser.add_argument("--device", default="/dev/dmsdio0", help="node of the SD host")
    parser.add_argument("--timeout", type=float, default=90,
                        help="seconds to wait for the shell and the card to be mounted")
    args = parser.parse_args()
    deadline = time.monotonic() + args.timeout
    partition = f"{args.device}/0p1"

    term = Terminal(connect("127.0.0.1", args.port, deadline))
    if not wait_for_prompt(term, deadline):
        print("✗ No shell prompt on the console UART")
        return 1

    mounted = wait_for_automount(term, deadline)
    if not check(term, f"ls {args.device}", lambda out: {"0", "0p1"} <= set(" ".join(out).split()),
                 f"card identified: {args.device}/0 and its partition {partition}"):
        return 1
    if not mounted:
        print(f"✗ automount did not mount the card at {MOUNT_POINT}")
        return 1
    print(f"✓ automount mounted the card at {MOUNT_POINT}")

    name, contents = next(iter(FILES.items()))
    token = f"sdcard-test-{int(time.time())}"
    checks = [
        (f"cat {MOUNT_POINT}/{name}", lambda out: contents.decode().strip() in out,
         f"{name} reads back as the image holds it"),
        (f"echo {token} > {MOUNT_POINT}/{WRITE_FILE}", no_errors,
         f"echo writes {WRITE_FILE}"),
        (f"umount {MOUNT_POINT}", no_errors,
         f"umount {MOUNT_POINT}"),
        (f"mount -t dmfatfs {partition} {REMOUNT_POINT}", no_errors,
         f"mount {partition} again at {REMOUNT_POINT}"),
        (f"cat {REMOUNT_POINT}/{WRITE_FILE}", lambda out: token in out,
         f"{WRITE_FILE} reads back from the card"),
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
