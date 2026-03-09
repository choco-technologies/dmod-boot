# Bug Report: Hard Fault When Mounting dmgpio via dmdevfs in Renode

## Summary

After fixing the infinite-loop in `mount_config_filesystem()` (see companion commit), the firmware
running in Renode triggers a **hard fault** at the point where `dmdevfs` initialises the `dmgpio`
device driver.  This document records the investigation findings so that the relevant bug can be
filed against the `dmgpio` or `dmdevfs` repository.

---

## Environment

| Item | Value |
|------|-------|
| Board | STM32F746G Discovery (`stm32f746g-disco`) |
| Renode platform | `platforms/boards/stm32f7_discovery-bb.repl` |
| dmgpio version | `0.4` (`dmgpio_port-v0.4-stm32f7`) |
| dmod-boot branch | `master` (commit `41e1b11…`) |

---

## How to Reproduce

1. Build `dmod-boot` for the `stm32f746g-disco` board **with** an embedded config
   filesystem that contains `board/stm32f746g-disco.ini` (i.e. a proper dmffs image):

   ```bash
   cmake -DCMAKE_BUILD_TYPE=Debug \
         -DBOARD=stm32f746g-disco \
         -DDMBOOT_EMULATION=ON \
         -DDMBOOT_CONFIG_DIR=<path-containing-board-stm32f746g-disco.ini> \
         -S . -B build
   cmake --build build
   cmake --build build --target install-firmware
   cmake --build build --target connect   # start Renode
   cmake --build build --target monitor-gdb  # observe output
   ```

2. Observe that the firmware log shows `dmgpio_port` being initialised (via `dmdevfs`) and
   then the `HardFault_Handler` fires — the log output stops with no further progress.

---

## Root Cause Analysis

### Boot sequence up to the fault

```
main()
  └─ mount_embedded_filesystems()
       ├─ dmvfs_mount_fs("dmramfs", "/", NULL)          – OK
       ├─ mount_config_filesystem()
       │    └─ dmvfs_mount_fs("dmffs", "/configs", …)  – OK (when config fs is embedded)
       └─ dmvfs_mount_fs("dmdevfs", "/dev", "/configs") – triggers hard fault
```

`dmdevfs` is initialised with `/configs` as the configuration directory.  During its mount
procedure it reads `board/stm32f746g-disco.ini` and calls the `dmgpio_port` driver's
initialisation entry point.

### What dmgpio_port does during initialisation

`dmgpio_port` (STM32F7 GPIO port driver, version 0.4) performs the following steps in its
`init` / `begin_configuration` / `finish_configuration` path:

1. Enables GPIO port clocks by writing to RCC AHB1ENR (`0x40023830`).
2. Configures GPIO pin modes by writing to GPIOx_MODER registers
   (e.g. GPIOB at `0x40020400`, GPIOC at `0x40020800`, GPIOI at `0x40022000`, etc.).
3. Optionally configures SYSCFG EXTICR registers for interrupt routing.

### The fault in Renode

Renode's `stm32f7_discovery-bb.repl` platform does include GPIO peripheral models, **but**
certain register accesses can trigger a hard fault because:

* **Unimplemented peripheral region**: The specific GPIO port address used by
  `dmgpio_port` for the STM32F746G Discovery may not be fully modelled.  Accesses to
  unmapped or partially-modelled MMIO addresses in Renode result in a CPU exception.
* **Register access before clock enable**: If `dmgpio_port` reads a GPIO register before
  confirming the clock is enabled (which the Renode model enforces differently from real
  hardware), the emulated peripheral may return an invalid value causing the driver to
  enter an invalid state or fault.
* **Missing peripheral in `.repl`**: `stm32f7_discovery-bb.repl` may omit specific
  peripherals that `dmgpio_port` requires (e.g. SYSCFG, a specific GPIO bank, or the
  full EXTI controller).

The hard fault fires inside `dmvfs_mount_fs("dmdevfs", "/dev", "/configs")` before
`dmlog_puts(ctx, "DMOD-Boot started\n")` is ever reached, so the Renode CI test fails.

---

## Proposed Fix (for dmgpio / dmdevfs)

**Option A – dmgpio_port**

`dmgpio_port` should gracefully handle the case where the underlying peripheral is not
accessible (e.g. because the code is running in an emulator that does not support the
peripheral).  Suggested changes:

* Check the `DMBOOT_EMULATION` environment variable on startup.  If set to `1`, skip any
  hardware-register access that is not strictly required for emulation testing.
* OR: wrap low-level register reads/writes in a `__attribute__((weak))` HAL layer so that
  platform ports (including Renode stubs) can provide no-op implementations.

**Option B – dmdevfs**

`dmdevfs` should not hard-fault when a device driver's `init` call fails or causes an
exception.  Suggested change:

* Catch / tolerate driver initialisation failures (return an error code from
  `dmdevfs_mount` instead of propagating the exception to the caller).
* This makes `dmdevfs` robust against partially-emulated hardware without requiring
  every driver to be emulation-aware.

---

## Relevant Files

| Repository | File | Line(s) |
|------------|------|---------|
| `dmod-boot` | `src/main.c` | `mount_embedded_filesystems()` → `dmvfs_mount_fs("dmdevfs", …)` |
| `dmod-boot` | `modules/modules.dmd` / `configs/board/stm32f746g-disco/flash.dmd` | `dmgpio board/stm32f746g-disco.ini` |
| `dmgpio` | `dmgpio_port` v0.4 | driver init / `begin_configuration` |
| `dmdevfs` | mount procedure | driver registration / init call |

---

## Workaround (do NOT use in production)

Removing `dmgpio board/stm32f746g-disco.ini` from
`configs/board/stm32f746g-disco/flash.dmd` prevents the driver from being loaded and
avoids the fault during emulation tests — **but this is a workaround, not a fix**, and
it means GPIO is unavailable at runtime.  The proper fix must be in `dmgpio` or
`dmdevfs` as described above.
