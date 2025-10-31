# dmod-boot

Dynamic Modules (dMOD) bootloader - A minimalistic embedded project for STM32 microcontrollers with integrated DMOD and dmheap support.

## Overview

dmod-boot is a minimal bootloader framework designed for embedded systems, specifically targeting STM32 ARM Cortex-M microcontrollers. It provides a clean, dependency-free foundation for dynamic module loading without relying on external libraries like STM32Cube.

### Key Features

- **DMOD Integration**: Full support for dynamic module loading and management
- **dmheap Memory Manager**: Module-aware heap allocation with automatic cleanup
- **No External Dependencies**: Pure bare-metal implementation without STM32Cube or other HAL libraries
- **Memory Ring Buffer Debug Output**: Built-in printf implementation using a memory ring buffer - works across all architectures
- **Multiple Architecture Support**: Linker scripts and startup code for various STM32 families
- **Minimal Footprint**: Optimized for size and efficiency
- **Easy to Extend**: Clean structure for adding support for additional microcontrollers
- **Integrated Development Workflow**: Built-in commands for building, flashing, and monitoring

## Supported Targets

Currently supported STM32 families:

| Target | MCU Family | Core | Flash | RAM | FPU |
|--------|------------|------|-------|-----|-----|
| STM32F746 | STM32F7 | Cortex-M7 | 1MB | 320KB | FPv5-SP-D16 |
| STM32F407 | STM32F4 | Cortex-M4 | 1MB | 128KB + 64KB CCM | FPv4-SP-D16 |

## Project Structure

```
dmod-boot/
├── src/                    # Source files
│   ├── dmod_printf.c      # Ring buffer based printf implementation
│   ├── dmod_sal_printf.c  # DMOD Printf and Mutex SAL implementation
│   ├── main.c             # Main application with DMOD and dmheap
│   ├── startup_stm32f746.c # Startup code for STM32F746
│   └── startup_stm32f407.c # Startup code for STM32F407
├── include/               # Header files
│   └── dmod_printf.h     # Printf API definitions
├── lib/                   # External libraries
│   ├── dmod/             # DMOD dynamic modules library
│   └── dmheap/           # dmheap memory manager (includes DMOD memory API)
├── linker/               # Linker scripts
│   ├── STM32F746xG.ld   # Linker script for STM32F746
│   └── STM32F407xG.ld   # Linker script for STM32F407
├── scripts/              # Utility scripts
│   └── dmod_log_monitor.py # OpenOCD log monitoring script
├── dmod-cfg.cmake        # DMOD configuration for CMake
├── dmod-cfg.mk          # DMOD configuration for Make
├── Makefile             # Build system (Make)
├── CMakeLists.txt       # Build system (CMake)
└── README.md           # This file
```

## Prerequisites

### Required Tools

- **ARM GCC Toolchain**: `arm-none-eabi-gcc` and related tools
  - Ubuntu/Debian: `sudo apt-get install gcc-arm-none-eabi`
  - macOS: `brew install arm-none-eabi-gcc`
  - Windows: Download from [ARM Developer](https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-rm)

- **Build System**: Choose one (or both)
  - **Make**: Build automation tool (usually pre-installed on Linux/macOS)
  - **CMake**: Cross-platform build system (version 3.15+)
    - Ubuntu/Debian: `sudo apt-get install cmake`
    - macOS: `brew install cmake`
    - Windows: Download from [cmake.org](https://cmake.org/download/)

### Optional Tools (for debugging)

- **Python 3**: For log monitoring script
- **OpenOCD**: For flashing and debugging
- **GDB**: For debugging
- **ST-Link** utilities as alternative to OpenOCD

## Quick Start

**Note**: When cloning this repository, make sure to initialize the submodules:

```bash
git clone --recursive https://github.com/choco-technologies/dmod-boot.git
# Or if already cloned:
git submodule update --init --recursive
```

### Using Make

#### 1. Build and Flash Firmware

```bash
# Build for default target (STM32F746)
make

# Build and flash to target
make install

# Or build for specific target
make TARGET=STM32F407
make install TARGET=STM32F407
```

### Using CMake (Recommended)

#### 1. Build and Flash Firmware

```bash
# Build for default target (STM32F746)
mkdir build
cd build
cmake ..
cmake --build .

# Or build for specific target
mkdir build
cd build
cmake .. -DTARGET=STM32F407
cmake --build .

# Flash to target (from build directory)
cmake --build . --target install-firmware
```

### 2. Connect and Monitor Logs

```bash
# Start OpenOCD in background (separate terminal)
make connect  # or from CMake: cmake --build . --target connect

# Monitor real-time logs (another terminal)
make monitor  # or from CMake: cmake --build . --target monitor
```

That's it! You should see live debug output from your microcontroller.

## Development Workflow

Both Make and CMake provide a complete development workflow:

### Using Make

| Command | Description |
|---------|-------------|
| `make` | Build firmware for default target (STM32F746) |
| `make TARGET=STM32F407` | Build for specific target |
| `make install` | Build and flash firmware to target |
| `make connect` | Start OpenOCD server for debugging |
| `make monitor` | Monitor live debug logs from target |
| `make clean` | Clean build artifacts |
| `make help` | Show all available commands |

### Using CMake

| Command | Description |
|---------|-------------|
| `cmake .. -DTARGET=STM32F746` | Configure for specific target |
| `cmake --build .` | Build firmware |
| `cmake --build . --target install-firmware` | Flash firmware to target |
| `cmake --build . --target connect` | Start OpenOCD server for debugging |
| `cmake --build . --target monitor` | Monitor live debug logs from target |
| `cmake --build . --target disasm` | Generate disassembly |

### Example Development Session (Make)

```bash
# 1. Build and flash your code
make clean
make install

# 2. In separate terminal - start debugging server
make connect

# 3. In another terminal - watch live logs
make monitor

# 4. Make code changes, then rebuild and reflash
make install
# Logs will update automatically in monitor terminal
```

### Example Development Session (CMake)

```bash
# 1. Build and flash your code
mkdir build && cd build
cmake .. -DTARGET=STM32F746
cmake --build .
cmake --build . --target install-firmware

# 2. In separate terminal - start debugging server
cmake --build . --target connect

# 3. In another terminal - watch live logs
cmake --build . --target monitor

# 4. Make code changes, then rebuild and reflash
cmake --build .
cmake --build . --target install-firmware
# Logs will update automatically in monitor terminal
```

## Building

### Using Make

#### Build for STM32F746

```bash
make TARGET=STM32F746
# or
make stm32f746
```

#### Build for STM32F407

```bash
make TARGET=STM32F407
# or
make stm32f407
```

#### Build All Targets

```bash
make all-targets
```

### Using CMake

#### Build for STM32F746

```bash
mkdir build && cd build
cmake .. -DTARGET=STM32F746
cmake --build .
```

#### Build for STM32F407

```bash
mkdir build && cd build
cmake .. -DTARGET=STM32F407
cmake --build .
```

#### Build All Targets

```bash
# Build STM32F746
mkdir build-f746 && cd build-f746
cmake .. -DTARGET=STM32F746
cmake --build .
cd ..

# Build STM32F407
mkdir build-f407 && cd build-f407
cmake .. -DTARGET=STM32F407
cmake --build .
cd ..
```

### Configure Ring Buffer Size

You can customize the ring buffer configuration:

#### Using Make

```bash
# Build with custom ring buffer settings
make TARGET=STM32F746 DMOD_LOG_TOTAL_SIZE=16384 DMOD_LOG_MAX_ENTRY_SIZE=1024

# Default values:
# DMOD_LOG_TOTAL_SIZE=8192       (total buffer size in bytes)
# DMOD_LOG_MAX_ENTRY_SIZE=512    (maximum size of a single log entry)
```

#### Using CMake

```bash
# Build with custom ring buffer settings
mkdir build && cd build
cmake .. -DTARGET=STM32F746 -DDMOD_LOG_TOTAL_SIZE=16384 -DDMOD_LOG_MAX_ENTRY_SIZE=1024
cmake --build .

# Default values:
# DMOD_LOG_TOTAL_SIZE=8192       (total buffer size in bytes)
# DMOD_LOG_MAX_ENTRY_SIZE=512    (maximum size of a single log entry)
```

### Clean Build Artifacts

#### Using Make

```bash
make clean
```

#### Using CMake

```bash
# Remove build directory
rm -rf build/
```

### View Help

```bash
make help
```

## Output Files

After building, the following files will be generated:

- **Make**: Files are in the `build/` directory
- **CMake**: Files are in the `build/` or your chosen build directory

Generated files:

- `<TARGET>.elf` - ELF executable with debug symbols
- `<TARGET>.bin` - Raw binary file for flashing
- `<TARGET>.hex` - Intel HEX format file
- `<TARGET>.map` - Linker map file showing memory layout
- `<TARGET>_dmod_addresses.txt` - Ring buffer addresses for debugging

## Using Memory Ring Buffer Debug Output

The project uses a memory ring buffer for debug output, providing a non-intrusive way to log messages that works across all architectures (not ARM-specific like ITM).

### API Usage

```c
#include "dmod_printf.h"

int main(void) {
    // Initialize log ring buffer
    Dmod_Log_Init();
    
    // Use printf-like formatting
    Dmod_Printf("Hello, World!\n");
    Dmod_Printf("Counter: %d\n", 42);
    Dmod_Printf("Hex: 0x%X\n", 0xDEADBEEF);
    
    // Clear buffer if needed (for re-synchronization)
    // Dmod_Log_Clear();
    
    while (1) {
        // Your code here
    }
    
    return 0;
}
```

### Supported Format Specifiers

- `%d`, `%i` - Signed decimal integer
- `%u` - Unsigned decimal integer
- `%x` - Unsigned hexadecimal (lowercase)
- `%X` - Unsigned hexadecimal (uppercase)
- `%c` - Character
- `%s` - String
- `%%` - Literal percent sign

### Ring Buffer Structure

The ring buffer consists of:
- **magic**: Magic number for validation (0x444D4F44 = "DMOD")
- **latest_id**: Most recent log entry ID (uint32_t) - easy to monitor for new logs
- **flags**: Command/status flags (uint32_t) - bit 0: clear buffer command
- **head_offset**: Offset to the newest entry in the buffer (uint32_t)
- **tail_offset**: Offset to the oldest entry in the buffer (uint32_t)
- **buffer**: Variable-length log entries stored sequentially

Each log entry in the buffer has:
- **id**: Unique incrementing ID (uint32_t)
- **length**: Message length in bytes (uint16_t)
- **data**: Message data (variable length)

The buffer automatically wraps around and overwrites old entries when full.

### Monitoring Logs

For live monitoring of debug output, use the integrated workflow:

```bash
# Start OpenOCD server
make connect

# Monitor logs in real-time (separate terminal)
make monitor
```

For advanced monitoring options and troubleshooting, see [scripts/README.md](scripts/README.md).

## Advanced Usage

### Manual Commands

If you need more control, you can run commands manually:

```bash
# Manual OpenOCD commands
openocd -f interface/stlink.cfg -f target/stm32f7x.cfg

# Manual monitoring with options
python3 scripts/dmod_log_monitor.py --target STM32F746 --debug

# Manual flashing
openocd -f interface/stlink.cfg -f target/stm32f7x.cfg \
    -c "program build/STM32F746.elf verify reset exit"
```

For detailed script usage and troubleshooting, see [scripts/README.md](scripts/README.md).

## Flashing the Firmware

### Using OpenOCD

```bash
openocd -f interface/stlink.cfg -f target/stm32f7x.cfg \
    -c "program build/STM32F746.elf verify reset exit"
```

### Using ST-Link

```bash
st-flash write build/STM32F746.bin 0x08000000
```

## Extending the Project

### Adding a New Target

1. Create a linker script in `linker/` directory (e.g., `STM32F103xB.ld`)
2. Create a startup file in `src/` directory (e.g., `startup_stm32f103.c`)
3. Add the new target to the Makefile
4. Update this README with the new target information

### Adding Features

The minimal design makes it easy to add features:

- **GPIO Control**: Add GPIO initialization and control functions
- **UART Communication**: Implement UART drivers
- **Timers**: Add timer configuration and interrupts
- **DMA**: Implement DMA transfers for efficient data movement

## Memory Layout

### STM32F746xG

- **Flash**: 0x08000000 - 0x080FFFFF (1MB)
- **RAM**: 0x20000000 - 0x2004FFFF (320KB)
  - Log ring buffer placed at start of RAM (configurable size)
- **DTCM RAM**: 0x20000000 - 0x2000FFFF (64KB)
- **ITCM RAM**: 0x00000000 - 0x00003FFF (16KB)

### STM32F407xG

- **Flash**: 0x08000000 - 0x080FFFFF (1MB)
- **RAM**: 0x20000000 - 0x2001FFFF (128KB)
  - Log ring buffer placed at start of RAM (configurable size)
- **CCM RAM**: 0x10000000 - 0x1000FFFF (64KB)

### Ring Buffer Memory Usage

With default configuration:
- **Total buffer size**: 8192 bytes
- **Max entry size**: 512 bytes
- **Control overhead**: 20 bytes
- **Total memory**: ~8.2 KB

The new dynamic allocation design is much more memory-efficient than the old fixed-size approach, using only the space needed for actual log messages.

## Contributing

Contributions are welcome! Please feel free to submit pull requests for:

- Additional STM32 family support
- Bug fixes
- Documentation improvements
- New features

## Integrated Libraries

### DMOD - Dynamic Modules

**dmod-boot** integrates the [DMOD (Dynamic Modules)](https://github.com/choco-technologies/dmod) library, which enables dynamic loading and unloading of modules at runtime. This allows you to:

- **Dynamically load modules**: Load functionality from `.dmf` files without recompiling
- **Manage dependencies**: Automatically handle module dependencies
- **Inter-module communication**: Modules can communicate via a common API
- **Resource management**: Efficiently manage system resources
- **Safe updates**: Update individual modules without affecting the entire system

DMOD is configured for bare-metal embedded systems with minimal overhead, making it ideal for STM32 microcontrollers.

### dmheap - Module-Aware Memory Manager

**dmod-boot** includes [dmheap](https://github.com/choco-technologies/dmheap), a sophisticated heap memory manager designed specifically for the DMOD framework. Features include:

- **Module-aware allocation**: Track which module owns each memory allocation
- **Automatic cleanup**: When a module is unloaded, all its allocations are freed automatically
- **Alignment support**: Allocate memory with specific alignment requirements (critical for DMA and hardware)
- **Fragmentation management**: Tools to concatenate free blocks and reduce fragmentation
- **Static buffer management**: Operates on a pre-allocated buffer (no reliance on system malloc)
- **Thread-safe operations**: Uses DMOD's critical section mechanisms

By default, dmheap is configured with 32KB of heap space, which can be adjusted in `CMakeLists.txt` or via the `DMHEAP_SIZE` configuration parameter.

## Configuration

### DMOD Configuration

The project includes `dmod-cfg.cmake` and `dmod-cfg.mk` files that configure DMOD for bare-metal embedded systems:

- Standard library features disabled (not available on bare-metal)
- Memory allocation provided by dmheap
- FastLZ compression enabled for module support
- Module limits: 10 modules, 5 dependencies
- Compression API disabled to save flash memory

### Memory Configuration

You can adjust memory allocation sizes:

```cmake
# In CMakeLists.txt or as CMake arguments
-DDMOD_LOG_TOTAL_SIZE=8192        # Log buffer size (default: 8KB)
-DDMOD_LOG_MAX_ENTRY_SIZE=512     # Max log entry size (default: 512 bytes)
-DDMHEAP_SIZE=32768               # Heap size (default: 32KB)
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related Projects

- [dmod](https://github.com/choco-technologies/dmod) - Dynamic modules library for embedded architectures
- [dmheap](https://github.com/choco-technologies/dmheap) - Module-aware heap memory manager for DMOD

## References

- [ARM Cortex-M7 Technical Reference Manual](https://developer.arm.com/documentation/ddi0489/latest/)
- [STM32F7 Reference Manual](https://www.st.com/resource/en/reference_manual/dm00124865.pdf)
- [STM32F4 Reference Manual](https://www.st.com/resource/en/reference_manual/dm00031020.pdf)
- [OpenOCD User's Guide](http://openocd.org/doc/html/index.html)

## Troubleshooting

### Build Issues

**Problem**: `arm-none-eabi-gcc: command not found`
- **Solution**: Install the ARM GCC toolchain (see Prerequisites)

**Problem**: Linker errors about undefined references
- **Solution**: Ensure all source files are included in the Makefile

**Problem**: Ring buffer takes too much RAM
- **Solution**: The new design uses dynamic allocation, so you only need to adjust `DMOD_LOG_TOTAL_SIZE` in the Makefile (e.g., 4096 bytes for smaller systems)

### Debugging Issues

**Problem**: Cannot connect to OpenOCD
- **Solution**: Make sure OpenOCD is running with TCL server enabled (port 6666)
- Check: `telnet localhost 4444` should connect to OpenOCD

**Problem**: No log output visible in monitor script
- **Solution**: Verify the target is running and calling `Dmod_Printf()`
- Check the ring buffer address in `build/<TARGET>_dmod_addresses.txt`
- Verify OpenOCD can read target memory

**Problem**: Program crashes or doesn't start
- **Solution**: Verify the correct linker script is used for your target MCU
- Check that ring buffer size doesn't exceed available RAM
