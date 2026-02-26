# dmod-boot

Dynamic Modules (dMOD) bootloader - A minimalistic embedded project for STM32 microcontrollers.

## Building

### Building for Hardware

```bash
mkdir build
cd build
cmake ..
cmake --build .
```

### Building for Renode Simulation

To build for Renode simulation (useful for automated testing without hardware):

```bash
mkdir build
cd build
cmake -DDMBOOT_EMULATION=ON ..
cmake --build .
```

With emulation mode enabled, the workflow targets (`install-firmware`, `connect`, `monitor-gdb`) work similarly to hardware mode but use Renode instead of OpenOCD.

**Why Renode?** Renode provides excellent STM32F7 Discovery board emulation with complete peripheral support, accurate memory mapping, and full interrupt controller implementation. This enables proper firmware execution and log capture via monitor-gdb, making it ideal for CI testing and verification.

### Building with Embedded Files

You can optionally embed binary files in ROM during the build:

```bash
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DSTARTUP_DMP_FILE=path/to/startup.dmp \
      -DUSER_DATA_FILE=path/to/user_data.dat \
      -DDMBOOT_CONFIG_DIR=path/to/config_directory \
      -S . -B build
cmake --build build
```

**Build Parameters:**
- `STARTUP_DMP_FILE` (optional) - Path to a startup package file (`.dmp`) that will be automatically loaded using `Dmod_AddPackageBuffer` at boot
- `USER_DATA_FILE` (optional) - Path to a user data file that will be embedded in ROM, with its address and size available via environment variables `USER_DATA_ADDR` and `USER_DATA_SIZE`
- `DMBOOT_CONFIG_DIR` (optional, defaults to `build/configs`) - Path to a directory that will be converted to a dmffs filesystem image and mounted at `/configs/` at boot time. By default, configuration files from `modules.dmd` are downloaded to this directory.
- `DMBOOT_EXTRA_FLASH_DMD_FILES` (optional) - Semicolon-separated list of additional `flash.dmd` files. Each file adds more flash modules to download at build time.
- `DMBOOT_EXTRA_FLASH_DMD_MANIFESTS` (optional) - Semicolon-separated list of manifest paths/URLs (one per extra flash.dmd file). Use this to specify a custom manifest for each extra flash.dmd file.
- `DMBOOT_EXTRA_SDCARD_DMD_FILES` (optional) - Semicolon-separated list of additional `sdcard.dmd` files. Each file adds more sdcard modules to download at build time.
- `DMBOOT_EXTRA_SDCARD_DMD_MANIFESTS` (optional) - Semicolon-separated list of manifest paths/URLs (one per extra sdcard.dmd file). Use this to specify a custom manifest for each extra sdcard.dmd file.
- `DMBOOT_MAIN_MODULE_PACKAGES_DIR` (optional) - Path to the local `packages` directory of the main module (e.g., `/path/to/dmgpio/build/packages`). When set together with `DMBOOT_MAIN_MODULE`, dmboot will copy the main module's `.dmf` directly from the local packages directory and resolve its dependencies using `manifest-local.dmm` from that directory (falling back to the remote manifest for any missing dependencies). This is useful for testing a locally-built module without re-publishing it.
- `DMBOOT_EMULATION` (optional) - Enable Renode simulation mode instead of hardware mode

**Automatic Build-Time Embedding:**
- `modules.dmp` - Automatically created and embedded during build if modules are specified in `modules/modules.dmd`. This file is loaded before `startup.dmp` at boot time. If no modules are defined, the file won't exist, which is not an error.

All parameters are optional. If not specified, the build will proceed with default settings.

## CMake Targets

The following targets work in both hardware mode (with OpenOCD) and Renode simulation mode. The workflow is identical regardless of the mode.

### `install-firmware`
Install firmware on the target.

- **Hardware mode:** Flashes firmware to the microcontroller via OpenOCD
- **Renode mode:** Copies firmware to a known location for Renode to use

```bash
cmake --build . --target install-firmware
```

### `connect`
Connect to the target and start the debug server.

- **Hardware mode:** Starts OpenOCD server that allows debugging and monitoring
- **Renode mode:** Starts Renode with GDB server on port 3333

```bash
cmake --build . --target connect
```

Keep this running in one terminal while using other debugging/monitoring tools.

### `monitor`
Monitor logs from the firmware in real-time via OpenOCD. This target:
- Automatically builds the `dmlog_monitor` tool for the host architecture
- Extracts the ring buffer address from the firmware's map file
- Runs `dmlog_monitor` with the correct configuration

**Usage:**

In one terminal, start OpenOCD:
```bash
cmake --build . --target connect
```

In another terminal, start the monitor:
```bash
cmake --build . --target monitor
```

The monitor will display logs from the firmware in real-time. Press Ctrl+C to exit.

### `monitor-gdb`
Monitor logs from the firmware in real-time via GDB server. This target:
- Automatically builds the `dmlog_monitor` tool for the host architecture
- Extracts the ring buffer address from the firmware's map file
- Runs `dmlog_monitor` with GDB backend configuration

This target works identically in both hardware and Renode modes, as it connects via the GDB protocol.

**Usage:**

In one terminal, start the debug server:
```bash
cmake --build . --target connect
```

In another terminal, start the monitor using GDB mode:
```bash
cmake --build . --target monitor-gdb
```

The monitor will connect to the GDB server at `localhost:3333`. Press Ctrl+C to exit.

**Note:** Both OpenOCD and Renode provide a GDB server on port 3333. The `monitor-gdb` target connects to this GDB server interface using the GDB Remote Serial Protocol, which is an alternative to using OpenOCD's telnet interface (port 4444) used by the `monitor` target. Both methods work equally well for monitoring logs.

### `debug`
Start GDB and connect to OpenOCD for debugging.

```bash
cmake --build . --target debug
```
