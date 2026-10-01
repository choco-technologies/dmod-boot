#!/usr/bin/env python3
"""Create the SD card image the Renode machine boots with.

The image has an MBR with a single FAT16 partition, labelled LABEL, holding
the files of FILES in its root directory - what a card formatted on a PC
looks like. It is built here, with only the standard library, because the CI
image has no mkfs.fat/mtools.

Usage: make_sdcard_image.py IMAGE [--size MIB]
"""
import argparse
import struct

LABEL = "DMODTEST"
# 8.3 names (upper case) -> contents
FILES = {
    "HELLO.TXT": b"Hello from the dmod-boot SD card test\n",
}

SECTOR = 512
PARTITION_START = 2048      # 1 MiB alignment, like fdisk/Windows
SECTORS_PER_CLUSTER = 4     # 2 KiB clusters: 4085..65524 clusters on 8..128 MiB is FAT16
RESERVED_SECTORS = 1
NUM_FATS = 2
ROOT_ENTRIES = 512
FAT16_LBA_TYPE = 0x0E
# Fixed timestamps keep the image the same on every run: 2026-01-01 00:00
FAT_DATE = ((2026 - 1980) << 9) | (1 << 5) | 1
FAT_TIME = 0


def fat_layout(total_sectors):
    """Return (sectors per FAT, cluster count) for a FAT16 volume of total_sectors."""
    root_sectors = ROOT_ENTRIES * 32 // SECTOR
    fat_sectors = 1
    while True:
        data_sectors = total_sectors - RESERVED_SECTORS - root_sectors - NUM_FATS * fat_sectors
        clusters = data_sectors // SECTORS_PER_CLUSTER
        needed = -(-(clusters + 2) * 2 // SECTOR)
        if needed <= fat_sectors:
            break
        fat_sectors = needed
    if not 4085 <= clusters <= 65524:
        raise ValueError(f"{clusters} clusters is no FAT16 volume - pick another size")
    return fat_sectors, clusters


def boot_sector(total_sectors, fat_sectors):
    bpb = struct.pack(
        "<3s8sHBHBHHBHHHII",
        b"\xEB\x3C\x90", b"DMODBOOT", SECTOR, SECTORS_PER_CLUSTER, RESERVED_SECTORS,
        NUM_FATS, ROOT_ENTRIES, 0, 0xF8, fat_sectors, 63, 255, PARTITION_START, total_sectors)
    ebpb = struct.pack("<BBBI11s8s", 0x80, 0, 0x29, 0x20261001, LABEL.encode().ljust(11), b"FAT16   ")
    sector = bytearray(SECTOR)
    sector[:len(bpb + ebpb)] = bpb + ebpb
    sector[510:512] = b"\x55\xAA"
    return sector


def dir_entry(name, attributes, cluster=0, size=0):
    base, _, ext = name.partition(".")
    short = base.ljust(8).encode() + ext.ljust(3).encode() if attributes != 0x08 else name.ljust(11).encode()
    return struct.pack("<11sBBBHHHHHHHI", short, attributes, 0, 0, FAT_TIME, FAT_DATE, FAT_DATE,
                       0, FAT_TIME, FAT_DATE, cluster, size)


def fat16_volume(total_sectors):
    fat_sectors, _ = fat_layout(total_sectors)
    cluster_size = SECTORS_PER_CLUSTER * SECTOR
    fat = [0xFFF8, 0xFFFF]
    root = bytearray(dir_entry(LABEL, 0x08))
    data = bytearray()
    for name, contents in FILES.items():
        first = len(fat)
        count = max(1, -(-len(contents) // cluster_size))
        fat += [first + i + 1 for i in range(count - 1)] + [0xFFFF]
        root += dir_entry(name, 0x20, first, len(contents))
        data += contents.ljust(count * cluster_size, b"\0")
    fat_bytes = struct.pack(f"<{len(fat)}H", *fat).ljust(fat_sectors * SECTOR, b"\0")
    return (boot_sector(total_sectors, fat_sectors) + bytes((RESERVED_SECTORS - 1) * SECTOR)
            + fat_bytes * NUM_FATS + root.ljust(ROOT_ENTRIES * 32, b"\0") + data)


def mbr(partition_sectors):
    sector = bytearray(SECTOR)
    struct.pack_into("<I", sector, 440, 0x444D4F44)  # disk signature "DMOD"
    # Bootable flag, CHS start/end (unused, LBA only), type, LBA start, sectors
    struct.pack_into("<B3sB3sII", sector, 446, 0x00, b"\xFE\xFF\xFF", FAT16_LBA_TYPE, b"\xFE\xFF\xFF",
                     PARTITION_START, partition_sectors)
    sector[510:512] = b"\x55\xAA"
    return sector


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("image")
    parser.add_argument("--size", type=int, default=64, help="card size in MiB (8..128)")
    args = parser.parse_args()

    total = args.size * 1024 * 1024 // SECTOR
    partition_sectors = total - PARTITION_START
    with open(args.image, "wb") as image:
        image.write(mbr(partition_sectors))
        image.seek(PARTITION_START * SECTOR)
        image.write(fat16_volume(partition_sectors))
        image.truncate(total * SECTOR)


if __name__ == "__main__":
    main()
