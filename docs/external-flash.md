# External flash (STM32F746G-DISCO)

The board's 16 MB Micron N25Q128A (QUADSPI) holds a [littlefs](https://github.com/littlefs-project/littlefs),
mounted at **`/ext`**. littlefs is made for NOR flash: power-loss resilient, it spreads the erases over the whole
chip (see the dmlittlefs documentation).

```
dmspiflash   the chip: /dev/dmspiflashx/flash (block device: read, write, erase)   - pins, bus and chip in one .ini
dmqspi       the QUADSPI bus (+ dmqspi_port: the controller, DMA2 stream 7)
dmlittlefs   the file system, mklittlefs creates it
ext service  configs/board/stm32f746g-disco/services/ext.ini: mount -t dmlittlefs ... /ext
```

## What lives there

| Path | What |
| --- | --- |
| `/ext/bin` | Modules (`.dmf`/`.dmfc`). On the module search path (`DMOD_REPO_PATHS`): flash modules take precedence over `/ext/bin`, which takes precedence over cards (`/mnt/<label>/bin`) |
| `/ext/secrets.vault` | The default dmsecrets vault: `DMBOOT_DMSECRETS_PATH` is `/ext/secrets.vault` for this board, so `DMSECRETS_PATH` points there at boot (wifid waits for it to appear) |
| anything else | Your files - it is the whole chip, the layout below `/ext` is up to you |

## First use: `format-ext`

A new chip has no file system, so the `ext` service cannot mount it (`No littlefs on '/dev/dmspiflashx/flash'` in the
log). Create one with the target - **all data in the flash is lost**, and it is never part of another target:

```bash
cmake --build build --target format-ext
```

It types into the device's console (`DMBOOT_UPLOAD_PORT`, as `upload-files`): `umount /ext` (when it was mounted),
`mklittlefs <device>`, `mount -t dmlittlefs ... /ext`, then lists `/ext`. A new boot mounts it by itself. The same by hand:

```
mklittlefs /dev/dmspiflashx/flash
mount -t dmlittlefs -o device=/dev/dmspiflashx/flash /ext
```

The console must be free: a terminal program open on the port (putty, minicom) takes the answers, so the scripts refuse
a port another process has open.

Options (the same for `mklittlefs` and the mount; geometry options must match): `offset=<bytes>,size=<bytes>` for a
part of the chip, `prog`, `read`, `cache`, `lookahead`, `block_cycles` - see dmlittlefs `docs/README.md`. Which device,
file system and mount point the targets use: `DMBOOT_EXT_DEVICE`, `DMBOOT_EXT_FS`, `DMBOOT_EXT_MKFS`, `DMBOOT_EXT_MOUNT`
(set by `configs/board/<BOARD>/board.cmake`; an empty `DMBOOT_EXT_DEVICE` - a board without it - leaves the targets out).

## Modules on the external flash: `ext.dmd`

`ext.dmd` is the third module list, next to `flash.dmd` (the firmware's ROM) and `sdcard.dmd` (a card): it exists as
`configs/common/ext.dmd`, `configs/mcu/<series>/<mcu>/ext.dmd` and `configs/board/<BOARD>/ext.dmd` (all optional) and
`DMBOOT_EXTRA_EXT_DMD_FILES` adds more. Same format as the others (a module per line; it uses the same manifest,
`DMBOOT_MANIFEST_URL`). The build downloads the modules into `build/ext/bin` (views into `build/ext/views`, licenses into
`build/ext/lic`), the rest of the packages stays in `build/packages/ext` - like `build/sdcard` - and

```bash
cmake --build build --target upload-ext
```

sends `build/ext` over the console (YMODEM) to `/ext`, so the modules land in **`/ext/bin`**, on the module search path.
`install-all` also downloads and sends these files, after installing the firmware and uploading the SD card files.
It uses `DMBOOT_UPLOAD_WAIT` while waiting for the console and requires the external flash to be formatted and mounted;
it never runs `format-ext` automatically.

Moving a module from `flash.dmd` to `ext.dmd` takes it out of the ROM - with its configuration: the `driver=`,
`service=` and `rules=` files of the ext modules go to `build/ext/cfg` and from there to `/ext/cfg`, which libsystemd
(units, rules) and `devscan` (drivers, through dmdevfs) load once `/ext` is mounted (and unload before it is unmounted). What stays in `flash.dmd`: everything that is
needed before `/ext` is mounted - the drivers and services, the file system (`dmlittlefs`) and the chain to the chip
(`dmspiflash`, `dmqspi`, `dmqspi_port`, `dmdma`, `dmclk`, `dmgpio`), the shell, and `ls`, `mount`, `umount`, `ymodem`
and `mklittlefs` (what `format-ext` / `upload-ext` and a recovery by hand need - with an empty or broken flash). An
application or a library loaded by name later can be on `/ext`.

For this board:

- **The firmware** (`flash.dmd`, `configs/common/flash.dmd`) holds only the way to `/ext` and the console: dmell, the
  file systems (dmffs, dmramfs, dmdevfs, dmlittlefs), libsystemd with `systemd`, `devscan` and `console`, the drivers of
  the clocks, the pins, the console UART (usart1), the SDRAM, DMA, the QUADSPI bus and the chip on it, and `ls`, `mount`,
  `umount`, `ymodem`, `tty`, `mklittlefs`, and `automount`, which mounts the SD card (see below). Built with `-DCMAKE_BUILD_TYPE=MinSizeRel` the image is about 404 kB
  (160 kB of it the core of the firmware); the `Debug` build type has no optimization at all and the same image is about
  485 kB.
- **Everything else is on `/ext`** (`ext.dmd`, `configs/common/tools.dmd`): the shell tools (`ps`, `cat`, `catini`,
  `mkdir`, `reboot`, `memory`, `service`, `rm`, `tree`, ...), the Ethernet and Wi-Fi stacks,
  telnetd, the crypto/secrets modules, the RTC and UTC/NTP, the SD card driver and its file system (dmsdio, dmfatfs,
  automount), the display (dmlcdtft, dmview), the touch panel and the audio. They are missing until `upload-ext` or
  `install-all` has been run, and they start when the `ext` service has mounted `/ext` (so the splash logo, which is on
  `/ext/views/` too, appears then - a second or two after the firmware starts). Expect more RAM in use than with
  everything in the firmware: measured on the STM32F746G-DISCO with the car HMI running, about 34 kB more of the main heap
  and 0.4 MB more of the SDRAM.
- **`automount` is in the firmware**, although nothing needs it to bring `/ext` up: the units of `/ext` stop when it is
  unmounted, and stopping automount's unit unmounts the cards it mounted - and the card holds the car HMI, which does
  not stop within the time the unmount gives it (the card stayed busy, `umount /ext` took minutes and left the system
  half stopped). With `automount` in the firmware, `umount /ext` stops the units of `/ext` (the network, the display,
  the audio, ...; about 15 s) and leaves the card alone; `mount` brings them back. It costs about 13 kB of the ROM
  (`automount`, `libautomount`, `dmblkid`, its unit and rules).
- **The car HMI demo** (`carhmi`), the image decoders (`dmimg_png`, `dmimg_jpeg`) and the MP3 decoder (`dmmp3`) are on
  the SD card (`sdcard.dmd`, sent by `upload-files`), loaded from `/mnt/<label>/bin` once the card is mounted. Its unit
  (`carhmi.ini`) is on the card too (`/mnt/<label>/cfg/services`): libsystemd starts it when the card is mounted and
  stops it before the card is unmounted.

## Notes

- The board's own units and rules (`configs/board/<BOARD>/services`, `.../rules`) are copied into the config
  filesystem next to the ones of the modules (`services/board/`, `rules/board/`).
- **In Renode**, the board loads `configs/renode/STM32F7_QUADSPI.cs`: QUADSPI at `0xA0001000`,
  IRQ 92, DMA2 stream 7, and the read-only mapped window at `0x90000000`. The model contains a
  16 MiB N25Q128A (`20 BA 18`). The chip starts empty: `scripts/run_renode_tests.sh` formats it and sends `build/ext` like `install-all` does on the board.
  See [Renode QUADSPI](renode-qspi.md) for image persistence and tests.
- `dmqspi` and `dmqspi_port` are listed in `flash.dmd` because `dmspiflash` talks to the bus only through the file
  system, so `dmf-get` does not pull them in as dependencies of it.
- The module search path is a CMake cache entry: an existing build directory keeps its old `DMOD_REPO_PATHS` (and
  `DMBOOT_DMSECRETS_PATH`) - pass `-DDMOD_REPO_PATHS=...` / `-DDMBOOT_DMSECRETS_PATH=/ext/secrets.vault` to it.
