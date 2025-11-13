# DMOD Boot Tests

This directory contains test files for DMOD Boot features.

## Test Data Files

Test data files are not committed to the repository. They need to be created before testing.

## Creating Test Data Files

### Create Test DMP Package

Build DMOD modules and create a test DMP package:

```bash
mkdir -p tests/data
# Build dmod modules
cd lib/dmod
mkdir -p build_modules
cd build_modules
cmake .. -DDMOD_MODE=DMOD_MODULE -DDMOD_TOOLS_NAME=arch/x86_64
cmake --build .
# Create DMP package
./bin/tools/todmp test_startup ./dmf ./test_startup.dmp
cp test_startup.dmp ../../../tests/data/
cd ../../..
```

### Create Test User Data

```bash
echo "Test User Data Content" > tests/data/test_user_data.dat
```

## Test Files

- `test_startup.dmp` - DMP package with sample modules for testing automatic loading
- `test_user_data.dat` - Sample user data file for testing environment variable setup

## Building with Embedded Files

Build DMOD Boot with test files embedded:

```bash
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DSTARTUP_DMP_FILE=tests/data/test_startup.dmp \
      -DUSER_DATA_FILE=tests/data/test_user_data.dat \
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
