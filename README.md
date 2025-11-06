# dmod-boot

Dynamic Modules (dMOD) bootloader - A minimalistic embedded project for STM32 microcontrollers.

## Embedding Files in ROM

The bootloader supports embedding optional files directly into the ROM image during the build process:

### 1. Startup Package (startup.dmp)

A package containing startup modules that will be automatically loaded at boot using `Dmod_AddPackageBuffer`.

**Usage:**
```bash
cmake -DSTARTUP_DMP_FILE=/path/to/startup.dmp ..
```

When provided, the startup.dmp file will be:
- Embedded in the `.startup_dmp` section of ROM
- Automatically loaded as a package during bootloader initialization
- Accessible via the DMOD package system

### 2. User Data File

An arbitrary data file that can contain any user-defined content.

**Usage:**
```bash
cmake -DUSER_DATA_FILE=/path/to/user_data.bin ..
```

When provided, the user_data file will be:
- Embedded in the `.user_data` section of ROM
- Its address and size exposed via environment variables:
  - `USER_DATA_ADDR`: Hexadecimal address of the data (e.g., "0x08010000")
  - `USER_DATA_SIZE`: Size in bytes (e.g., "1024")

### Example Build Command

```bash
mkdir build
cd build
cmake -DSTARTUP_DMP_FILE=/path/to/startup.dmp \
      -DUSER_DATA_FILE=/path/to/user_data.bin \
      ..
make
```

### Notes

- Both files are optional - the bootloader will work normally if neither is provided
- Files are stored in ROM with 16-byte alignment
- The embedded data can be accessed at runtime via the linker symbols or environment variables
- Environment variable storage uses a simple internal implementation (note: `Dmod_SetEnv` API is not yet fully functional as mentioned in the original requirements)
