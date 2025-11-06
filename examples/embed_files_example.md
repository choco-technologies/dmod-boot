# Example: Embedding Files in ROM

This example demonstrates how to embed startup.dmp and user_data files into the bootloader ROM image.

## Step 1: Create Test Files

Create sample files to embed:

```bash
# Create a sample startup.dmp file
echo "Sample startup package data" > /tmp/startup.dmp

# Create a sample user data file
echo "Sample user data content" > /tmp/user_data.bin
```

## Step 2: Configure CMake with Files

Configure the build with the file paths:

```bash
mkdir build
cd build

cmake .. \
    -DSTARTUP_DMP_FILE=/tmp/startup.dmp \
    -DUSER_DATA_FILE=/tmp/user_data.bin
```

## Step 3: Build the Bootloader

```bash
make
```

## Expected Output

During the build, you should see messages like:

```
-- Embedding startup.dmp file: /tmp/startup.dmp
-- Embedding user_data file: /tmp/user_data.bin
...
[ XX%] Copying startup.dmp file
[ XX%] Converting startup.dmp to object file
[ XX%] Copying user_data file
[ XX%] Converting user_data to object file
...
```

## Runtime Behavior

When the bootloader runs, it will:

1. **Startup Package**: Automatically load the embedded startup.dmp using `Dmod_AddPackageBuffer`
   - Log message: `Loading startup.dmp: Start=0x..., Size=... bytes`
   - On success: `Startup package loaded successfully, index=...`

2. **User Data**: Set environment variables for the embedded user data
   - `USER_DATA_ADDR`: Hexadecimal address (e.g., "0x08010000")
   - `USER_DATA_SIZE`: Size in bytes
   - Log message: `Environment variables set: USER_DATA_ADDR=0x..., USER_DATA_SIZE=...`

## Building Without Embedded Files

If you don't provide the file parameters, the bootloader will work normally:

```bash
cmake ..
make
```

You'll see:
```
-- No startup.dmp file provided
-- No user_data file provided
```

And at runtime:
```
No startup.dmp provided
No user_data provided
```

## Memory Layout

The embedded files are placed in ROM with 16-byte alignment:

- `.startup_dmp` section: Contains the startup.dmp data
- `.user_data` section: Contains the user_data data

Both sections are placed after the main program code and before the data section.

## Accessing Embedded Data

### In C Code

The linker provides weak symbols that can be accessed:

```c
extern char __startup_dmp_start__ __attribute__((weak));
extern char __startup_dmp_end__ __attribute__((weak));
extern char __user_data_start__ __attribute__((weak));
extern char __user_data_end__ __attribute__((weak));

// Check if data is present
void* startup_addr = (void*)&__startup_dmp_start__;
void* startup_end = (void*)&__startup_dmp_end__;
size_t startup_size = (size_t)((uintptr_t)startup_end - (uintptr_t)startup_addr);

if (startup_size > 0) {
    // Data is available
    // Use startup_addr to access the data
}
```

### Via Environment Variables (User Data Only)

The user data address and size are also stored as environment variables:
- `USER_DATA_ADDR`: String representation of the address
- `USER_DATA_SIZE`: String representation of the size in bytes

Note: The environment variable implementation is currently a simple internal storage mechanism, as the full `Dmod_SetEnv` API is not yet functional.
