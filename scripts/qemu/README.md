# ESP32-S3 tests in QEMU

Regression tests of the ESP32-S3 boards on CI, the counterpart of Renode for the STM32F7. They use the official Espressif QEMU fork
(`esp-develop-9.2.2-20261109`, machine `esp32s3`), which runs the real ROM, the selector and the firmware.

| File | What |
|---|---|
| `build-qemu.sh <dir>` | builds (in CI it is in the Docker image, docker/Dockerfile.env, as $QEMU_ESP32S3_DIR) the QEMU from the release sources with `patches/` (the ROMs come from the release binary) |
| `make-images.py <build> <out>` | `flash.bin` (selector + bank A, 4 MB) and `efuse.bin` (PSRAM_CAP = octal 8 MB) |
| `test_qemu_esp32s3.py <qemu> <images>` | boot, shell, `/dev`, `ps`, format `/ext` and the SD card (FAT, automount), write, restart, read back |
| `../run_qemu_tests.sh <build> <qemu>` | the two above together |

Board covered now: `elecrow-dis08070h`. The QEMU flags: `-m 8M` (the octal PSRAM), `-global driver=ssi_psram,property=is_octal,value=true`,
the eFuse image (the PSRAM is detected from it), the flash as `if=mtd` (QEMU writes into it, so the test works on a copy).

## Patches to QEMU (to be sent upstream to espressif/qemu)

1. `0001`: the IRAM (0x40370000) is an alias of the DRAM (0x3FC88000), as in the chip. Without it the code that is copied through the data
   bus (the vectors, the modules loaded to the RAM) is not seen by the instruction bus.
2. `0002`: the flash window of the cache is refreshed when the cache is invalidated (`Cache_Invalidate_Addr`). Without it the data written
   to the flash by the SPI controller (/ext) is not seen through the window.

3. `0003`: the general purpose SPI (GP-SPI2, `esp32s3_gpspi.c`: the registers of the master, W0..W15, the transfers through the GDMA), an SD
   card in the SPI mode on it (`-drive file=sd.img,if=sd,index=1`: a power of two in size), and the GPIO pads: the GPIO of the S3 now keeps the
   output and enable registers and drives the lines wired to the pads (the chip select of the card is the pad 10, as on the Elecrow board).
   The pins of the GPIO matrix are not modelled: the SPI is wired to the card whatever the pins are.
4. `0004`: the SD card model in the SPI mode answered CMD13 with the CSD (so the host saw "illegal command" and never found the card ready)
   and did not accept CMD9/CMD10 in the transfer state.

Not emulated (so not tested here): the RGB panel, the touch, the radio, the exact timing.
