# CMake Options

This document describes all CMake options available when building dmod-boot.

## Main Build Options

These options are defined in the top-level `CMakeLists.txt` and control the overall build configuration.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `TARGET` | STRING | `STM32F746xG` | Target microcontroller. Supported values: `STM32F746xG`, `STM32F407G`. Ignored when `BOARD` is set. |
| `BOARD` | STRING | *(empty)* | Board name (optional). When set, `TARGET` is derived from `configs/board/<BOARD>/board.cmake`. Example: `stm32f746g-disco`. |
| `STARTUP_DMP_FILE` | FILEPATH | *(empty)* | Path to an optional `.dmp` startup package file to embed in ROM. Loaded using `Dmod_AddPackageBuffer` at boot. |
| `USER_DATA_FILE` | FILEPATH | *(empty)* | Path to an optional user data file to embed in ROM. Its address and size are accessible via `USER_DATA_ADDR` and `USER_DATA_SIZE` environment variables. |
| `DMBOOT_CONFIG_DIR` | PATH | `<build>/configs` | Path to a directory that will be converted to a dmffs filesystem image and mounted at `/configs/` at boot time. |
| `DMBOOT_MAIN_MODULE` | STRING | `dmell` | Name of the main module to start after boot. |
| `DMBOOT_EXTRA_FLASH_DMD_FILES` | STRING | *(empty)* | Semicolon-separated list of additional `flash.dmd` files to include. Each file adds more flash modules to download at build time. |
| `DMBOOT_EXTRA_SDCARD_DMD_FILES` | STRING | *(empty)* | Semicolon-separated list of additional `sdcard.dmd` files to include. Each file adds more sdcard modules to download at build time. |
| `DMBOOT_MANIFEST_URL` | STRING | *(empty)* | Manifest path/URL to use with `dmf-get -m` flag when downloading the main module. Flash and sdcard dependency modules (from `.dmd` files) always use the default public manifest. |
| `DMBOOT_EMULATION` | BOOL | `OFF` | Enable Renode emulation mode instead of hardware mode (OpenOCD). |

## VFS Options

These options are defined in `configs/dmvfs-cfg.cmake` and configure the virtual filesystem.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DMBOOT_MAX_MOUNT_POINTS` | STRING | `100` | Maximum number of VFS mount points. |
| `DMBOOT_MAX_OPEN_FILES` | STRING | `1000` | Maximum number of simultaneously open files. |

## DMOD Library Options

These options are defined in `configs/dmod-cfg.cmake` and configure the DMOD library.

### Standard Library Integration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DMOD_USE_STDLIB` | BOOL | `OFF` | Enable use of the C standard library. |
| `DMOD_USE_GETENV` | BOOL | `OFF` | Enable use of the `getenv` function. |
| `DMOD_USE_STDIO` | BOOL | `OFF` | Enable use of the `stdio` library. |
| `DMOD_USE_ASSERT` | BOOL | `OFF` | Enable use of the `assert` function. |
| `DMOD_USE_PTHREAD` | BOOL | `OFF` | Enable use of the `pthread` library. |
| `DMOD_USE_MMAN` | BOOL | `OFF` | Enable use of memory management functions (`mman.h`). |
| `DMOD_USE_ALIGNED_ALLOC` | BOOL | `OFF` | Enable use of aligned allocation. |
| `DMOD_USE_ALIGNED_MALLOC_MOCK` | BOOL | `OFF` | Enable aligned malloc mock when aligned allocation is not available. |
| `DMOD_USE_REALLOC` | BOOL | `OFF` | Enable use of the `realloc` function. |
| `DMOD_USE_ENVIRON` | BOOL | `OFF` | Enable use of the `environ` variable. |
| `DMOD_USE_TERMIOS` | BOOL | `OFF` | Enable use of the `termios` library. |
| `DMOD_USE_TIME_H` | BOOL | `OFF` | Enable use of the `time.h` library. |
| `DMOD_USE_FASTLZ` | BOOL | `ON` | Enable use of the FastLZ compression library. |
| `DMOD_USE_EXCEPTIONS` | BOOL | `OFF` | Enable use of C++ exceptions. |

### Built-in Implementations

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DMOD_IMPLEMENT_PRINTF` | BOOL | `ON` | Implement `printf` inside DMOD (avoids linking the full stdio library). |
| `DMOD_IMPLEMENT_SCANF` | BOOL | `OFF` | Implement `scanf` inside DMOD. |
| `DMOD_BUILTIN_COMPRESSION_API` | BOOL | `ON` | Enable the built-in compression API. Can use a lot of flash memory; decompression-only is usually sufficient. |

### Module System Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DMOD_MAX_MODULES` | STRING | `100` | Maximum number of modules that can be registered. |
| `DMOD_MAX_REQUIRED_MODULES` | STRING | `15` | Maximum number of required modules per module. |
| `DMOD_MODE` | STRING | `DMOD_SYSTEM` | Operating mode of the DMOD system. |
| `DMOD_EXTERNAL_REGISTRATION` | BOOL | `ON` | Enable external registration of modules (required by `dmvfs` and `dmlist` libraries). |

### System Version

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DMOD_SYSTEM_VERSION_MAJOR` | STRING | `0` | Major version of your system. |
| `DMOD_SYSTEM_VERSION_MINOR` | STRING | `1` | Minor version of your system. |

### File System Paths

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DMOD_DMFC_DIR` | STRING | `/flash/dmfc` | Directory for DMFC (compiled module) files on the target filesystem. |
| `DMOD_DMF_DIR` | STRING | `/flash/dmf` | Directory for DMF (module) files on the target filesystem. |
| `DMOD_REPO_DIR` | STRING | `<DMOD_DMF_DIR>` | Path to the default module repository on the target filesystem. |
| `DMOD_REPO_PATHS` | STRING | `<DMOD_DMF_DIR>:<DMOD_DMFC_DIR>` | Colon-separated list of all module repository paths on the target filesystem. |

### Sub-library Build Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `DMOD_BUILD_TESTS` | BOOL | `OFF` | Enable building of DMOD library tests. |
| `DMOD_BUILD_EXAMPLES` | BOOL | `OFF` | Enable building of DMOD library examples. |
| `DMOD_BUILD_TOOLS` | BOOL | `OFF` | Enable building of DMOD tools (e.g. `todmp`). |
| `DMOD_BUILD_TEMPLATES` | BOOL | `OFF` | Enable building of DMOD module templates. |

## Usage Examples

### Minimal build with default settings

```bash
cmake -S . -B build
cmake --build build
```

### Build for a specific target

```bash
cmake -DTARGET=STM32F407G -S . -B build
cmake --build build
```

### Build using a board preset

```bash
cmake -DBOARD=stm32f746g-disco -S . -B build
cmake --build build
```

### Build for Renode emulation

```bash
cmake -DDMBOOT_EMULATION=ON -S . -B build
cmake --build build
```

### Build with embedded startup package and custom config directory

```bash
cmake -DSTARTUP_DMP_FILE=/path/to/startup.dmp \
      -DDMBOOT_CONFIG_DIR=/path/to/configs \
      -S . -B build
cmake --build build
```

### Adjust module system limits

```bash
cmake -DDMOD_MAX_MODULES=200 \
      -DDMBOOT_MAX_MOUNT_POINTS=50 \
      -DDMBOOT_MAX_OPEN_FILES=200 \
      -S . -B build
cmake --build build
```
