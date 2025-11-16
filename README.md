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
      -DDMBOOT_ROMFS_DIR=./rom-fs \
      -S . -B build
cmake --build build
```

**Build Parameters:**
- `STARTUP_DMP_FILE` (optional) - Path to a startup package file (`.dmp`) that will be automatically loaded using `Dmod_AddPackageBuffer` at boot
- `USER_DATA_FILE` (optional) - Path to a user data file that will be embedded in ROM, with its address and size available via environment variables `USER_DATA_ADDR` and `USER_DATA_SIZE`
- `DMBOOT_ROMFS_DIR` (optional) - Path to a directory that will be converted to a read-only ROM filesystem using dmffs and embedded in the firmware. The filesystem will be automatically mounted at `/romfs/` during boot.
- `DMBOOT_EMULATION` (optional) - Enable Renode simulation mode instead of hardware mode

All parameters are optional. If not specified, the build will proceed with default settings.

### ROM File System (ROMFS) Support

The bootloader includes built-in support for the [dmffs](https://github.com/choco-technologies/dmffs) module, which provides a read-only file system stored in flash memory. When you specify `-DDMBOOT_ROMFS_DIR=<path>` during the build:

1. The specified directory is converted to a binary filesystem image using the `make_dmffs` tool
2. The filesystem binary is embedded in the firmware ROM
3. At boot, the `modules.dmp` package (containing dmffs, dmfsi, and make_dmffs modules) is automatically loaded
4. The ROM filesystem is mounted at `/romfs/` and accessible via the DMVFS API

**Example:**
```bash
# Create a directory with files to embed
mkdir rom-fs
echo "Configuration data" > rom-fs/config.txt
echo "Static content" > rom-fs/readme.txt

# Build with ROM filesystem
cmake -DDMBOOT_ROMFS_DIR=./rom-fs -S . -B build
cmake --build build

# The files will be accessible at /romfs/config.txt and /romfs/readme.txt at runtime
```

**Note:** The ROM filesystem is read-only. For runtime file modifications, use other filesystem modules like FatFS on SD card or RamFS in RAM.

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
