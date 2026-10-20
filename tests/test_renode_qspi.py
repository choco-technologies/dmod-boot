#!/usr/bin/env python3
"""Exercise QUADSPI/N25Q128A through Renode's bus, without firmware or hardware.

Usage: python3 tests/test_renode_qspi.py [--renode /path/to/renode]
Tests use their own temporary flash image. No board or existing image is touched.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = 0xA0001000
DMA = 0x40026400
STREAM = DMA + 0x10 + 7 * 0x18
RAM = 0x20020000


class Script:
    def __init__(self, image):
        self.lines = [
            f'include @{ROOT}/configs/renode/STM32F7_QUADSPI.cs',
            f'include @{ROOT}/configs/renode/STM32F7_Audio.cs',
            'mach create',
            'machine LoadPlatformDescriptionFromString "ram: Memory.MappedMemory @ sysbus 0x20020000 { size: 0x1000 }"',
            'machine LoadPlatformDescriptionFromString "dma: DMA.STM32F7_AudioDMA @ sysbus 0x40026400"',
            'machine LoadPlatformDescriptionFromString "qspi: SPI.STM32F7_QUADSPI @ sysbus 0xA0001000 { '
            f'imageFile: \\\"{image}\\\"; DMARequest -> dma@7 }}"',
            'machine LoadPlatformDescriptionFromString "window: SPI.STM32F7_QSPIWindow @ sysbus 0x90000000 { controller: qspi }"',
        ]
        self.expected = []
        self.write(BASE, 1)

    def write(self, address, value, width='DoubleWord'):
        self.lines.append(f'sysbus Write{width} 0x{address:X} 0x{value:X}')

    def read(self, address, expected, label, width='DoubleWord'):
        self.lines.append(f'sysbus Read{width} 0x{address:X}')
        self.expected.append((expected, label))

    def command(self, op, mode=0, size=0, address=None, quad=False):
        self.write(BASE + 0xC, 0x1B)
        self.write(BASE + 0x10, max(0, size - 1))
        ccr = op | 0x100 | (mode << 26)
        if size:
            ccr |= (3 if quad else 1) << 24
        if address is not None:
            ccr |= 0x2400  # one address line, 24 bits
        self.write(BASE + 0x14, ccr)
        if address is not None:
            self.write(BASE + 0x18, address)

    def program(self, address, value, enable=True):
        if enable:
            self.command(0x06)
        self.command(0x32, size=4, address=address, quad=True)
        self.write(BASE + 0x20, value)
        self.read(BASE + 8, 2, 'program completes')

    def array_read(self, address, expected, label):
        self.command(0xEB, mode=1, size=4, address=address, quad=True)
        self.read(BASE + 0x20, expected, label)
        self.read(BASE + 8, 2, 'read completes')

    def run(self, renode, directory, name):
        script = directory / f'{name}.resc'
        script.write_text('\n'.join(self.lines + ['quit']) + '\n')
        result = subprocess.run([renode, '--disable-xwt', '--console', '-e', f'include @{script}'],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', result.stdout.decode(errors='replace'))
        (directory / f'{name}.log').write_text(text)
        values = [int(v, 16) if v.startswith('0x') else v == 'True'
                  for v in re.findall(r'^\s*(0x[0-9a-fA-F]+|True|False)\s*$', text, re.M)]
        if result.returncode or len(values) != len(self.expected):
            raise AssertionError(f'Renode did not execute all checks ({len(values)}/{len(self.expected)}):\n{text}')
        for actual, (expected, label) in zip(values, self.expected):
            assert actual == expected, f'{label}: expected 0x{expected:X}, got 0x{actual:X}\n{text}'
        print(f'PASS {name}: {len(values)} bus checks')


def exercise(renode, directory):
    image = directory / 'qspi.img'
    s = Script(image)
    s.command(0x9F, mode=1, size=3)
    for value in [0x20, 0xBA, 0x18]:
        s.read(BASE + 0x20, value, 'JEDEC ID', 'Byte')
    s.read(BASE + 8, 2, 'ID transfer completed')
    s.write(BASE, 1 | (31 << 8))  # tail shorter than FIFO threshold must be readable
    s.command(0x9F, mode=1, size=3)
    s.read(BASE + 8, 0x326, 'short final FIFO sets TCF and FTF')
    s.read(BASE + 0x20, 0x18BA20, 'word read consumes only remaining bytes')
    s.write(BASE, 1)
    s.array_read(0x100, 0xFFFFFFFF, 'new flash erased')
    s.program(0x100, 0, enable=False)
    s.array_read(0x100, 0xFFFFFFFF, 'program without WREN ignored')
    s.program(0x100, 0x12345678)
    s.program(0x100, 0xFFFFFFFF)
    s.array_read(0x100, 0x12345678, 'program cannot change zero to one')
    s.command(0x05, mode=1, size=1)
    s.read(BASE + 0x20, 0, 'WEL cleared after program', 'Byte')
    s.program(0x1FE, 0xAABBCCDD)
    s.command(0x03, mode=1, size=2, address=0x1FE)
    s.read(BASE + 0x20, 0xCCDD, 'halfword access', 'Word')
    s.array_read(0x100, 0x12340238, 'page program wraps within 256 bytes')
    s.command(0x20, address=0x100)
    s.array_read(0x100, 0x12340238, 'erase without WREN ignored')
    s.program(0x1100, 0xABCDEF01)
    s.command(0x06)
    s.command(0x20, address=0x123)
    s.array_read(0x100, 0xFFFFFFFF, '4K erase aligns down')
    s.array_read(0x1100, 0xABCDEF01, '4K erase preserves neighbor')
    s.command(0x06)
    s.command(0xD8, address=0x1100)
    s.array_read(0x1100, 0xFFFFFFFF, '64K erase')

    # DMA2 stream 7, channel 3, byte elements and memory increment.
    for i in range(16):
        s.write(RAM + i * 4, 0x01020300 + i)
    s.command(0x06)
    s.command(0x32, size=64, address=0x4000, quad=True)
    s.write(STREAM + 4, 64)
    s.write(STREAM + 8, BASE + 0x20)
    s.write(STREAM + 12, RAM)
    s.write(STREAM, (3 << 25) | (1 << 10) | (1 << 6) | 1)
    s.write(BASE, 5)
    s.read(STREAM + 4, 0, 'TX DMA NDTR')
    s.read(BASE + 8, 2, 'TX DMA TCF')
    s.write(BASE, 1)

    # Match the firmware order: CCR, DMA enable, CR.DMAEN, AR.
    s.write(BASE + 0xC, 0x1B)
    s.write(BASE + 0x10, 63)
    s.write(BASE + 0x14, 0x070025EB)
    s.write(STREAM + 4, 64)
    s.write(STREAM + 8, BASE + 0x20)
    s.write(STREAM + 12, RAM + 0x100)
    s.write(STREAM, (3 << 25) | (1 << 10) | 1)
    s.write(BASE, 5)
    s.read(STREAM + 4, 64, 'RX DMA waits for address')
    s.write(BASE + 0x18, 0x4000)
    s.read(STREAM + 4, 0, 'RX DMA NDTR')
    s.read(BASE + 8, 2, 'RX DMA TCF')
    for i in range(16):
        s.read(RAM + 0x100 + i * 4, 0x01020300 + i, 'DMA byte sequence')

    # Automatic polling: ready matches; WEL=1 does not; ABORT recovers.
    s.write(BASE, 1 | (1 << 22) | (1 << 19))
    s.write(BASE + 0x24, 1)
    s.write(BASE + 0x28, 0)
    s.command(0x05, mode=2, size=1)
    s.read(BASE + 8, 8, 'auto-poll match and automatic stop')
    s.lines.append('sysbus.qspi IRQ IsSet')
    s.expected.append((True, 'status match IRQ asserted'))
    s.write(BASE + 0xC, 8)
    s.lines.append('sysbus.qspi IRQ IsSet')
    s.expected.append((False, 'clearing SMF clears IRQ'))
    s.write(BASE + 0x24, 2)
    s.write(BASE + 0x28, 2)
    s.command(0x05, mode=2, size=1)
    s.read(BASE + 8, 0x20, 'nonmatching poll stays busy')
    s.write(BASE, 3)
    s.read(BASE, 1, 'ABORT self-clears')
    s.read(BASE + 8, 2, 'abort completes')

    s.command(0xEB, mode=3, size=1, quad=True)
    s.read(0x90004000, 0x01020300, 'mapped read')
    s.write(0x90004000, 0)
    s.read(0x90004000, 0x01020300, 'mapped writes ignored')
    s.write(BASE, 3)
    s.read(0x90004000, 0xFFFFFFFF, 'aborted mapping unavailable')
    s.command(0x06)
    s.command(0x66)
    s.command(0x99)
    s.command(0x05, mode=1, size=1)
    s.read(BASE + 0x20, 0, 'reset clears WEL', 'Byte')
    s.lines.append('sysbus.qspi Reset')
    s.write(BASE, 1)
    s.array_read(0x4000, 0x01020300, 'reset preserves flash')
    s.command(0xFF)
    s.read(BASE + 8, 1, 'unsupported opcode TEF')
    s.run(renode, directory, 'registers-dma')
    assert image.stat().st_size == 16 * 1024 * 1024

    # A second emulator process must reopen the programmed array, not erase it.
    s = Script(image)
    s.array_read(0x4000, 0x01020300, 'persistent image reload')
    s.command(0x06)
    s.command(0xC7)
    s.array_read(0x4000, 0xFFFFFFFF, 'chip erase')
    s.run(renode, directory, 'persistence')
    assert image.read_bytes() == b'\xff' * (16 * 1024 * 1024)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--renode', default='renode')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='dmod-qspi-') as temp:
        exercise(args.renode, Path(temp))
