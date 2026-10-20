# QUADSPI and external flash in Renode

`BOARD=stm32f746g-disco` loads `configs/renode/STM32F7_QUADSPI.cs` when Renode
starts. No Renode rebuild or firmware driver changes are needed. The model was
checked with Renode 1.15.3 (Mono and .NET).

The controller is at `0xA0001000`, with IRQ 92 and DMA2 stream 7/channel 3.
The built-in chip represents the board's 16 MiB Micron N25Q128A, JEDEC ID
`20 BA 18`. The read-only memory-mapped window starts at `0x90000000`.
DMA2 uses the existing `STM32F7_AudioDMA` model even without audio capture:
it implements byte transfers and the remaining count the QSPI driver checks.

## Persistent image

For example:

```sh
cmake -S . -B build-renode -DBOARD=stm32f746g-disco -DDMBOOT_EMULATION=ON \
  -DDMBOOT_RENODE_QSPI_IMAGE="$PWD/build-renode/qspi.img"
cmake --build build-renode --target install-firmware
cmake --build build-renode --target connect
```

The model creates a missing image as 16777216 bytes of `0xFF`. Existing images
must have exactly that size. It writes changes after each page program or erase.
Do not run two emulator instances against the same writable image. An empty
`DMBOOT_RENODE_QSPI_IMAGE` keeps the chip in memory only: resets preserve the
array, but a new emulator process starts erased.

A new chip has no littlefs. The `ext` boot unit reports a mount failure and the
shell remains available. In the **emulator's console**, provision it once:

```text
mklittlefs /dev/dmspiflashx/flash
mount -t dmlittlefs -o device=/dev/dmspiflashx/flash /ext
echo persistent-data > /ext/example.txt
cat /ext/example.txt
```

`mklittlefs` destroys any previous filesystem on the selected device. When using
an image file, the next emulator process mounts `/ext` through the normal boot
unit; `cat /ext/example.txt` then reads the saved data. The image holds raw flash
bytes, not a preformatted filesystem. No files from `build/ext` are injected.

## Coverage and limits

The functional model supports indirect 8/16/32-bit FIFO accesses, transfer and
error flags, threshold/status IRQs, DMA requests, AND/OR status polling with
automatic stop, abort, and memory-mapped reads. Supported commands:

- JEDEC ID (`9E`, `9F`), WREN/WRDI (`06`, `04`), status and flag status (`05`, `70`, `50`);
- reads (`03`, `0B`, `6B`, `EB`), page program (`02`, `32`), 4 KiB/64 KiB/chip erase (`20`, `D8`, `C7`);
- volatile configuration read/write (`85`, `81`, `65`, `61`), reset enable/reset (`66`, `99`).

Programming requires WREN, only changes 1 bits to 0, wraps within a 256-byte
page and clears WEL. Erase requires WREN and aligns to the containing sector.
Reset clears volatile state without erasing the array. Unsupported commands
raise the controller's transfer-error flag and log a warning.

Operations complete instantly; this is not a timing or electrical model. Pin
mux, clock rates, dummy-cycle timing, flash wear, protection registers, SFDP,
OTP, suspend/resume, dual flash and DDR are outside its scope. It does not test
real DMA/cache coherency or prove hardware timing correctness.

Register layout and behavior follow ST's [RM0385](https://www.st.com/resource/en/reference_manual/dm00124865-stm32f7-series-advanced-armbased-32bit-mcus-stmicroelectronics.pdf).
The flash command set follows Micron's N25Q128A 3 V datasheet
(`n25q_128mb_3v_65nm`) and the commands used by `dmspiflash`.

## Tests

```sh
python3 tests/test_renode_qspi.py --renode /path/to/renode
./scripts/run_renode_tests.sh "$PWD" "$PWD/build-renode-test"
```

The first test drives the Renode bus without firmware: JEDEC, write-enable,
program/erase rules, FIFO widths, DMA byte order/count, polling IRQ, abort,
mapped reads, reset and persistence across two emulator processes.

The firmware suite explicitly selects an in-memory chip for each run. Its
external-flash step formats that disposable chip, mounts littlefs, writes and
reads a file, unmounts/remounts and checks the contents again. The standalone
`scripts/test_renode_ext.py --format` is only for such a disposable emulator;
it must not be aimed at a console connected to real hardware or valuable data.
