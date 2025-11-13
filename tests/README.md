# DMOD Boot Tests

This directory contains test files for DMOD Boot features.

## Test Data Files

The `data/` directory contains sample files used for testing ROM embedding:

- `test_startup.dmp` - Sample startup package file for testing Dmod_AddPackageBuffer
- `test_user_data.bin` - Sample user data file for testing environment variable setup

## Building with Embedded Files

To build DMOD Boot with embedded test files:

```bash
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DSTARTUP_DMP_FILE=tests/data/test_startup.dmp \
      -DUSER_DATA_FILE=tests/data/test_user_data.bin \
      -S . -B build
cmake --build build
```

## Verifying Embedded Files

After building, you can verify the embedded files by checking the map file:

```bash
grep -A 5 "\.embedded\.startup_dmp" build/dmboot.map
grep -A 5 "\.embedded\.user_data" build/dmboot.map
```

You should see the sections with their addresses and sizes.
