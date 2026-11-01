# The selector on the ESP32-S3

The selector (`selector/`) runs on the ESP32-S3 as the **second stage bootloader**: the image at offset 0 of the flash, loaded
by the ROM into the RAM. Board: `configs/board/esp32s3-lcd28` (16 MB flash, USB-Serial/JTAG on the USB port).

Status: the selector starts, maps the flash, reads and writes its store (a counter kept in the store survives resets), starts
a bank (checked on the board with a test firmware, `selector/fw/testbank-esp`: the code runs from the flash through the
instruction cache, the table of the selector works from it, and the same build starts from the bank A and from the bank B)
and logs over USB. **Not done:** the real firmware (dmboot) for the ESP32-S3; the watchdog for an image on trial is a stub
(`DMSEL_WATCHDOG_MS` has to stay 0); the trial/rollback path was checked on the host and on the STM32 only.

## Build

```bash
pip install esptool pyserial          # the esptool submodule of the ESP-IDF in /tools is empty
cmake -S selector/fw -B build-selector-esp -DDMSEL_BOARD=esp32s3-lcd28 -DDMSEL_ARCH=xtensa -DDMSEL_ARCH_CORE=lx7 \
      -DDMSEL_MCU_SERIES=esp32s3 -DDMSEL_MCU=esp32s3fn16r8 [-DDMSEL_ESPTOOL=<path>] [-DDMSEL_SELFTEST=ON]
cmake --build build-selector-esp      # dmsel.elf, dmsel.bin (the image in the format of ESP-IDF, made by esptool elf2image)
```

`-DDMSEL_SELFTEST=ON` adds a counter of the starts kept in the store (`dmsel: selftest starts: N`): it writes the flash at
every start, use it to check a port, not to leave on a board.

## Flash and log

```bash
esptool --port /dev/ttyACM0 write-flash --flash-mode keep --flash-freq keep --flash-size keep 0x0 build-selector-esp/dmsel.bin
python3 selector/tools/esp_console.py --reset --seconds 8
```

`esp_console.py` opens the port with DTR/RTS low, resets the chip (RTS = EN) and prints what comes out; any terminal on
`/dev/ttyACM0` shows the same, but only the lines logged after it was opened (the FIFO of the endpoint is 64 bytes and the
text is dropped while nobody reads it). When nothing can be started the selector repeats `idle, nothing to start` every 2 s.

## What is where

| | |
| --- | --- |
| flash 0x000000 | the selector, 64 kB (the ROM loads it: IRAM 0x403c1700, DRAM 0x3fcd9700, the place of the bootloader of ESP-IDF) |
| flash 0x010000 | the store, 64 kB (32 kB used) |
| flash 0x100000 | slot of the bank A, 3 MB: the image (0x2F0000), then the file system of the bank, `/`, 64 kB (0x3F0000) |
| flash 0x400000 | slot of the bank B, the same (file system at 0x6F0000) |
| flash 0x700000 | `/ext`, 9 MB, common to both banks |
| 0x3C000000 | all 16 MB of the flash seen by the data bus (mapped by `dmsel_mcu_flash_init`) |

Everything is aligned to 64 kB, the page of the MMU. The layout is `configs/board/esp32s3-lcd28/board.cmake`; the selector
takes it from there at build time (`dmsel_layout`), so a change of it means a new selector. The writable file system of a
bank is not the selector's: the selector knows the bank as its image only and never touches the file system; the plugin that
mounts it (a `dmflash` port for the ESP32-S3, not written yet) has to keep to the file system of the running bank and `/ext`.
Flash operations of such a plugin must run with the cache suspended, from the RAM, and with the interrupts that live in the
flash masked (see `selector/mcu/esp32s3/esp32s3fn16r8/flash.c`).

Installing: erase the store (`esptool erase-region 0x10000 0x10000`) and write `dmsel.bin` at 0x0, as `install-firmware` does for
the STM32 (the state is rebuilt from the banks).

Before the selector the board had the Arduino/ESP-IDF image of its vendor; the store (0x10000) is where its application was.
To go back: `esptool write-flash 0x0 <backup of the first 4 MB>`.

## A bank on the ESP32-S3

The image of a bank is what the STM32 has: the header of the selector (512 bytes, `dmsel_mkimage.py`) and the bytes of the
code. The flash is not in the memory of the chip, so before the jump the selector (`dmsel_mcu_prepare_jump`, `image.c`) maps
the pages of the bank into a window, switches the instruction cache on and jumps to `window + entry_offset`:

| | |
| --- | --- |
| code window | `0x43000000` (the code bus: the entries 256.. of the MMU) |
| data window | `0x3D000000` (the data bus: the same entries, the same pages) |
| the image | its first byte is the first byte of the window: the header, then the code at +0x200 (`entry_offset`) |

The window is the same for both banks, so **one build of the firmware starts from either bank** (the firmware asks the
selector which one it is: `init( &state, DMSEL_RUNNING_STARTED, scratch )`). The code bus cannot read bytes, so the read-only
data are linked for the data window (`0x3D000000 + offset`), but lie in the image right after the code (the load address is
in the code window, `AT()` in `selector/fw/testbank-esp/bank.ld`: objcopy makes the image by the load addresses). The data
and the code that has to run from the RAM follow them, the start of the firmware copies them (as on the STM32).

The MMU entries 0..255 are the selector's own mapping of the whole flash (the table of the selector reads the store and the
banks through it while the firmware runs), so the firmware must not touch them. The firmware must not use the RAM of the
selector either (`0x403c1700..0x403c9700`, `0x3fcd9700..0x3fce9700`); the table is at `0x3fcd9700` (`DMSEL_TABLE_ADDRESS`).

Test firmware:

```bash
selector/fw/testbank-esp/build.sh <dir> [version]            # <dir>/bank.bin
esptool --port /dev/ttyACM0 write-flash 0x100000 <dir>/bank.bin   # the bank A (0x400000 for the bank B)
esptool --port /dev/ttyACM0 erase-region 0x10000 0x10000          # the store: the state is rebuilt, the newest image starts
python3 selector/tools/esp_console.py --reset --seconds 8
```
