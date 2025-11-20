# ROM File Embedding Feature

## Overview
DMOD Boot supports embedding binary files into ROM at build time. This allows you to package your application modules and custom data directly into the bootloader image.

### Supported Files

1. **`startup.dmp`** (optional) - A DMOD package file containing startup modules
   - Automatically loaded and executed during boot
   - Can contain multiple DMF (DMOD Module Format) modules
   - Useful for preloading essential system modules or application code

2. **`user_data`** (optional) - Custom binary data file
   - Embedded in ROM and accessible via environment variables
   - Address available as `USER_DATA_ADDR` environment variable
   - Size available as `USER_DATA_SIZE` environment variable
   - Can contain configuration, assets, or any custom data

3. **`modules.dmp`** (automatic, build-time generated) - A DMOD package file containing modules from the `modules/` directory
   - Automatically created during the build process if modules are specified in `modules/modules.dmd`
   - Loaded before `startup.dmp` during boot
   - If no modules are defined, the file won't exist, which is not an error
   - Can contain library modules to be enabled or application modules to be run

## How It Works

When DMOD Boot starts:
1. It checks if a `modules.dmp` package is embedded in ROM
2. If present, the package is automatically loaded using `Dmod_Load()` and enabled (for library modules) or run (for application modules)
3. It checks if a `startup.dmp` package is embedded in ROM
4. If present, the package is automatically loaded using `Dmod_Load()` and its main module (if specified) is executed
5. User data (if embedded) has its location made available through environment variables for your modules to access

## Building with Embedded Files

### Basic Build (no embedded files)
```bash
cmake -DCMAKE_BUILD_TYPE=Debug -DTARGET=STM32F746xG -S . -B build
cmake --build build
```

### Build with Startup Package
```bash
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DSTARTUP_DMP_FILE=path/to/startup.dmp \
      -S . -B build
cmake --build build
```

### Build with User Data
```bash
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DUSER_DATA_FILE=path/to/config.bin \
      -S . -B build
cmake --build build
```

### Build with Both Files
```bash
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DSTARTUP_DMP_FILE=path/to/startup.dmp \
      -DUSER_DATA_FILE=path/to/config.bin \
      -S . -B build
cmake --build build
```

## Creating DMP Packages

To create a `.dmp` package file, you need to build DMOD modules and package them using the `todmp` tool:

### 1. Build DMOD Tools (SYSTEM mode)
First, build DMOD in SYSTEM mode to compile the `todmp` tool:

```bash
cd lib/dmod
mkdir -p build
cd build
cmake .. -DDMOD_MODE=DMOD_SYSTEM -DDMOD_TOOLS_NAME=arch/x86_64
cmake --build .
```

### 2. Build DMOD Modules (MODULE mode)
Reconfigure the same build directory to MODULE mode to generate `.dmf` files:

```bash
cmake .. -DDMOD_MODE=DMOD_MODULE -DDMOD_TOOLS_NAME=arch/x86_64
cmake --build .
```

This creates `.dmf` (DMOD Module Format) files in the `dmf/` directory.

### 3. Create DMP Package
Use the `todmp` tool (built in step 1) to package the DMF files:

```bash
# Create package with a specific main module
./bin/tools/todmp package_name ./dmf ./output.dmp main_module_name

# Or create package without a main module
./bin/tools/todmp package_name ./dmf ./output.dmp
```

### 4. List Package Contents
```bash
./bin/tools/todmp -l ./output.dmp
```

## Accessing Embedded User Data

Your modules can access the embedded user data through environment variables:

```c
#include "dmenv.h"

// Get the default environment context
dmenv_ctx_t env = dmenv_get_default();

// Read user data address
uint32_t user_data_addr = 0;
if (dmenv_geti(env, "USER_DATA_ADDR", &user_data_addr)) {
    // Read user data size
    uint32_t user_data_size = 0;
    if (dmenv_geti(env, "USER_DATA_SIZE", &user_data_size)) {
        // Access the user data
        void* data_ptr = (void*)user_data_addr;
        // Use data_ptr and user_data_size...
    }
}
```

## Verifying Embedded Files

After building, you can verify that files were properly embedded by checking the map file:

```bash
# Check for modules.dmp symbols
grep "__modules_dmp" build/dmboot.map

# Check for startup.dmp symbols
grep "__startup_dmp" build/dmboot.map

# Check for user_data symbols
grep "__user_data" build/dmboot.map
```

All should show the start, end, and size symbols with their addresses. Note that `modules.dmp` symbols will always be present, but may show zero size if no modules were defined.
