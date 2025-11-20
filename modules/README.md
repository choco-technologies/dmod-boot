# Modules Package Feature

This directory contains the modules package build system that automatically downloads, packages, and embeds modules into the firmware.

## Overview

The `modules.dmd` file lists modules that should be automatically:
1. Downloaded for the target architecture using `dmf-get`
2. Packaged into a single `modules.dmp` file using `todmp`
3. Embedded in the firmware ROM
4. Loaded and enabled at boot time

## Module List File Format

The `modules.dmd` file uses a simple line-based format:

```
# Comments start with #
# Empty lines are ignored

# Module specification format: module_name[@version]
dmffs@1.1
another_module@2.0
some_module
```

### Syntax:
- **One module per line**
- **Comments**: Lines starting with `#` are ignored
- **Module name**: Required, the name of the module to fetch
- **Version**: Optional, specified with `@version` (e.g., `@1.1`)
- **Empty lines**: Ignored

## Build Process

During the build:

1. **CMake reads** `modules.dmd` and parses the module list
2. **Architecture detection**: Determines the target architecture (e.g., `arch/armv7/cortex-m4`)
3. **Tool building**: Builds the `todmp` tool from DMOD in SYSTEM mode
4. **Module download**: For each module:
   - Calls `dmf-get module_name --arch <target_arch> --type dmf`
   - Downloads the `.dmf` file to `build/modules/dmf/`
5. **Packaging**: Creates `build/modules/modules.dmp` containing all downloaded modules
6. **Embedding**: Embeds the package in ROM at section `.embedded.modules_dmp`
7. **Runtime loading**: At boot, the bootloader loads and enables all modules

## Requirements

- **dmf-get**: Must be available in PATH or use the Docker container
- **todmp**: Built automatically from DMOD library
- **Target architecture**: Detected from CMake configuration

## Accessing Modules at Runtime

Modules from the package are automatically loaded and enabled before `startup.dmp` is loaded. This means:
- All modules are available for use by startup applications
- Modules are already initialized and ready to use
- No manual loading required

## Disabling Module Packaging

If you don't want to use the module packaging feature:
1. Remove or rename `modules.dmd`
2. The build system will skip module packaging automatically

## Example Usage

1. Edit `modules/modules.dmd`:
   ```
   # Core filesystem module
   dmffs@1.1
   
   # Additional modules as needed
   # mymodule@1.0
   ```

2. Build the firmware:
   ```bash
   mkdir build && cd build
   cmake -DTARGET=STM32F746xG ..
   cmake --build .
   ```

3. The `modules.dmp` will be automatically created and embedded

## Troubleshooting

### dmf-get not found
If `dmf-get` is not in your PATH, the build will show a warning but continue. To fix:
- Install dmf-get
- Or use the Docker container: `docker run -it chocotechnologies/dmboot:1.0.0`

### Module download fails
Check:
- Internet connection
- Module name and version are correct
- dmf-get has access to the module repository

### Package creation fails
Check:
- At least one module was downloaded successfully
- todmp tool was built correctly
- Sufficient disk space for the package

## Technical Details

### Files Created During Build
- `build/modules/dmf/*.dmf` - Downloaded module files
- `build/modules/modules.dmp` - Final package
- `build/modules/modules_downloaded.stamp` - Download completion marker
- `build/modules/dmod_tools_build/` - todmp tool build directory

### Linker Symbols
The embedded package provides these symbols:
- `__modules_dmp_start` - Start address of the package in ROM
- `__modules_dmp_end` - End address of the package in ROM
- `__modules_dmp_size` - Size of the package in bytes

### Memory Layout
The package is embedded in ROM in this order:
1. `.text` (code)
2. `.embedded.startup_dmp`
3. `.embedded.user_data`
4. `.embedded.modules_dmp` ← New section
5. Other sections...
