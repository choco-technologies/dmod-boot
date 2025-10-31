# DMOD and dmheap Integration Guide

This document explains how DMOD and dmheap are integrated into dmod-boot and how to use them in your embedded applications.

## Overview

**dmod-boot** now includes two powerful libraries:

1. **DMOD** - Dynamic module loading and management system
2. **dmheap** - Module-aware heap memory manager

These libraries work together to provide a flexible, dynamic module system for STM32 microcontrollers.

## Architecture

### Memory Layout

```
STM32 Flash Memory (1MB):
┌────────────────────────────────┐
│ .text (code)                   │
│ .rodata (constants)            │
│ .inputs (DMOD inputs)          │ ← Added by dmod-common.ld
│ .outputs (DMOD outputs)        │ ← Added by dmod-common.ld
│ .data (init data)              │
└────────────────────────────────┘

STM32 RAM:
┌────────────────────────────────┐
│ .data (initialized variables)  │
│ .bss (zero-initialized)        │
│ .dmod_log_ring (8KB)          │ ← Debug log ring buffer
│ dmheap buffer (32KB)           │ ← Dynamic heap for modules
│ Stack                          │
└────────────────────────────────┘
```

### Component Interaction

```
┌──────────────────────────────────────────────────┐
│              Your Application                     │
│          (src/main.c)                            │
└─────────┬────────────────────────────────────────┘
          │ Uses DMOD API
          ↓
┌──────────────────────────────────────────────────┐
│         DMOD Library (lib/dmod)                  │
│  - Module loading/unloading                      │
│  - Dependency management                         │
│  - API registration                              │
└─────────┬────────────────────────────────────────┘
          │ Calls SAL functions
          ↓
┌─────────────────────┐  ┌──────────────────────────┐
│  dmheap             │  │  dmod_sal_printf.c       │
│  (lib/dmheap)       │  │  - Dmod_Printf()         │
│  - Dmod_MallocEx()  │  │  - Mutex stubs           │
│  - Dmod_FreeEx()    │  │                          │
│  - Memory tracking  │  │  dmod_printf.c           │
│  - Module cleanup   │  │  - Ring buffer log       │
└─────────────────────┘  └──────────────────────────┘
```

## Configuration

### CMake Configuration (dmod-cfg.cmake)

The `dmod-cfg.cmake` file configures DMOD for bare-metal embedded systems:

- **Standard Library**: Disabled (not available on bare-metal)
- **Memory Allocation**: Provided by dmheap
- **Compression**: FastLZ enabled for module support
- **Module Limits**: 10 modules max, 5 dependencies max
- **CPU Target**: ARM Cortex-M

### Build Configuration

You can customize the build in `CMakeLists.txt` or via command-line arguments:

```bash
# Build with custom heap size
cmake .. -DDMHEAP_SIZE=65536

# Build with larger log buffer
cmake .. -DDMOD_LOG_TOTAL_SIZE=16384

# Combine multiple options
cmake .. -DTARGET=STM32F407 -DDMHEAP_SIZE=16384 -DDMOD_LOG_TOTAL_SIZE=4096
```

## Using DMOD API

### Basic Memory Allocation

```c
#include "dmod.h"

void example_memory(void) {
    // Allocate memory for your module
    void* buffer = Dmod_MallocEx(1024, "my_module");
    if (buffer != NULL) {
        // Use the buffer
        memset(buffer, 0, 1024);
        
        // Free when done
        Dmod_FreeEx(buffer, "my_module");
    }
}
```

### Aligned Memory Allocation

Useful for DMA operations and hardware peripherals:

```c
#include "dmod.h"

void example_aligned_memory(void) {
    // Allocate 1KB buffer aligned to 64 bytes (for DMA)
    void* dma_buffer = Dmod_AlignedMallocEx(64, 1024, "dma_module");
    if (dma_buffer != NULL) {
        // Use for DMA operations
        // ...
        
        // Free when done
        Dmod_FreeEx(dma_buffer, "dma_module");
    }
}
```

### Module-Aware Cleanup

One of the most powerful features is automatic memory cleanup:

```c
#include "dmod.h"

void module_lifecycle(void) {
    // Allocate multiple buffers for a module
    void* buf1 = Dmod_MallocEx(256, "temp_module");
    void* buf2 = Dmod_MallocEx(512, "temp_module");
    void* buf3 = Dmod_MallocEx(1024, "temp_module");
    
    // Do work with buffers...
    
    // Free ALL memory allocated by "temp_module" at once
    Dmod_FreeModule("temp_module");
    // buf1, buf2, and buf3 are all freed automatically!
}
```

### Logging with DMOD Printf

```c
#include "dmod.h"

void example_logging(void) {
    // Use DMOD Printf (goes to ring buffer)
    Dmod_Printf("System initialized\n");
    Dmod_Printf("Temperature: %d C, Humidity: %d%%\n", 25, 60);
    Dmod_Printf("Status: 0x%X\n", 0xDEADBEEF);
}
```

## Example Application

The `src/main.c` file demonstrates the integration:

```c
#include "dmod_printf.h"
#include "dmod.h"
#include "dmheap.h"

/* Heap buffer for dmheap */
#define DMHEAP_SIZE 32768
static char g_heap_buffer[DMHEAP_SIZE] __attribute__((aligned(8)));

int main(void) {
    // Initialize log ring buffer
    Dmod_Log_Init();
    
    // Initialize dmheap
    if (dmheap_init(g_heap_buffer, DMHEAP_SIZE, 8)) {
        Dmod_Printf("Heap initialized: %d bytes\n", DMHEAP_SIZE);
    }
    
    Dmod_Printf("=== dmod-boot with DMOD & dmheap ===\n");
    
    // Test basic allocation
    void* ptr = Dmod_MallocEx(256, "main");
    if (ptr) {
        Dmod_Printf("Allocated 256 bytes at %p\n", ptr);
        Dmod_FreeEx(ptr, "main");
    }
    
    // Test aligned allocation
    void* aligned = Dmod_AlignedMallocEx(64, 512, "main");
    if (aligned) {
        Dmod_Printf("Allocated 512 bytes aligned to 64\n");
        Dmod_FreeEx(aligned, "main");
    }
    
    // Main loop
    while (1) {
        // Your application code
    }
}
```

## Implementation Details

### DMOD SAL Functions

The System Abstraction Layer (SAL) is split between dmheap and local implementation:

**Memory Functions (provided by dmheap library):**

| Function | Purpose | Implementation |
|----------|---------|----------------|
| `Dmod_MallocEx` | Allocate memory | Provided by `lib/dmheap` |
| `Dmod_FreeEx` | Free memory | Provided by `lib/dmheap` |
| `Dmod_AlignedMallocEx` | Aligned allocation | Provided by `lib/dmheap` |
| `Dmod_ReallocEx` | Reallocate memory | Provided by `lib/dmheap` |
| `Dmod_FreeModule` | Free module memory | Provided by `lib/dmheap` |

**Other Functions (implemented in `src/dmod_sal_printf.c`):**

| Function | Purpose | Implementation |
|----------|---------|----------------|
| `Dmod_Printf` | Logging | Uses existing `dmod_printf` |
| `Dmod_Mutex_*` | Mutex operations | No-op (single-threaded) |

### dmheap Configuration

dmheap must be initialized explicitly in `main.c`:
```c
static char g_heap_buffer[DMHEAP_SIZE] __attribute__((aligned(8)));

int main(void) {
    // Initialize dmheap
    if (dmheap_init(g_heap_buffer, DMHEAP_SIZE, 8)) {
        Dmod_Printf("Heap initialized\n");
    }
    // ... rest of application
}
```

Configuration:
- **Buffer Size**: 32KB (configurable via `DMHEAP_SIZE`)
- **Alignment**: 8 bytes (suitable for ARM Cortex-M)
- **Location**: Static buffer in RAM (g_heap_buffer)

## Memory Usage

Typical memory usage for the integrated system:

| Component | Flash | RAM |
|-----------|-------|-----|
| Startup code | ~2KB | - |
| DMOD library | ~20KB | ~2KB |
| dmheap | ~4KB | 32KB (heap) |
| dmod_printf | ~2KB | 8KB (ring buffer) |
| dmod_sal | ~1KB | - |
| **Total** | **~29KB** | **~42KB** |

This leaves plenty of space for your application code and additional modules.

## Linker Script Integration

Both linker scripts (`STM32F746xG.ld` and `STM32F407xG.ld`) include:

```ld
/* DMOD sections for dynamic module support */
INCLUDE dmod-common.ld
```

This adds the `.inputs` and `.outputs` sections needed by DMOD for API registration and module communication.

## Troubleshooting

### Build Issues

1. **Submodules not initialized**:
   ```bash
   git submodule update --init --recursive
   ```

2. **Linker errors about dmod-common.ld**:
   - Ensure the linker can find `lib/dmod/scripts/`
   - Check that `target_link_options` includes the DMOD scripts directory

3. **Undefined references to DMOD functions**:
   - Verify `target_link_libraries` includes both `dmod` and `dmheap`
   - Check that `dmod_sal_printf.c` is in the sources list
   - Ensure dmheap is properly initialized in `main.c`

### Runtime Issues

1. **Heap allocation failures**:
   - Increase `DMHEAP_SIZE` in CMakeLists.txt
   - Check available RAM in your target MCU

2. **No log output**:
   - Ensure `Dmod_Log_Init()` is called at startup
   - Verify OpenOCD is running and connected
   - Check the monitor script is reading the correct address

## Next Steps

1. **Load Dynamic Modules**: Create `.dmf` module files and load them at runtime
2. **Define Module APIs**: Use DMOD's API system for inter-module communication
3. **Optimize Memory**: Adjust heap and buffer sizes based on your needs
4. **Add Features**: Extend the system with your application-specific code

## References

- [DMOD Documentation](https://github.com/choco-technologies/dmod)
- [dmheap Documentation](https://github.com/choco-technologies/dmheap)
- [dmod-boot Repository](https://github.com/choco-technologies/dmod-boot)
