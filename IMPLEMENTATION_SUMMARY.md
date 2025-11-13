# ROM File Embedding Implementation Summary

## Overview
This implementation adds the ability to embed binary files into ROM during build time, with two optional files:
1. `startup.dmp` - Startup package automatically loaded at boot
2. `user_data` - User data file with address/size exposed via environment variables

## Implementation Details

### 1. Helper Script (`scripts/embed_binary.cmake`)
- **Purpose**: Provides `embed_binary_file()` function to convert binary files into ELF object files
- **How it works**: 
  - Uses `objcopy` to convert binary data into ARM ELF object files
  - Places data in custom sections (e.g., `.embedded.startup_dmp`)
  - Relies on linker script to create proper symbols

### 2. Build Configuration (`CMakeLists.txt`)
- **New CMake variables**:
  - `STARTUP_DMP_FILE` (optional) - Path to startup.dmp file
  - `USER_DATA_FILE` (optional) - Path to user_data file
- **Build process**:
  - Checks if files exist
  - Calls `embed_binary_file()` to create object files
  - Links object files into final executable

### 3. Linker Script (`linker/common.ld`)
- **New sections added**:
  - `.embedded.startup_dmp` - Contains startup.dmp data
  - `.embedded.user_data` - Contains user_data data
- **Symbols created** (for each section):
  - `__startup_dmp_start`, `__startup_dmp_end`, `__startup_dmp_size`
  - `__user_data_start`, `__user_data_end`, `__user_data_size`

### 4. Runtime Loading (`src/main.c`)
- **startup.dmp handling**:
  - Checks if `__startup_dmp_size > 0`
  - If yes, calls `Dmod_AddPackageBuffer()` to load the package
  - Logs success/failure
- **user_data handling**:
  - Checks if `__user_data_size > 0`
  - If yes, sets environment variables:
    - `USER_DATA_ADDR` - Address of user_data in ROM
    - `USER_DATA_SIZE` - Size of user_data in bytes
  - Uses `dmenv_seti()` to set as hex values

## Usage Examples

### Building without embedded files (default):
```bash
cmake -DCMAKE_BUILD_TYPE=Debug -DTARGET=STM32F746xG -S . -B build
cmake --build build
```

### Building with both files embedded:
```bash
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DSTARTUP_DMP_FILE=path/to/startup.dmp \
      -DUSER_DATA_FILE=path/to/user_data.dat \
      -S . -B build
cmake --build build
```

### Building with only startup.dmp:
```bash
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DSTARTUP_DMP_FILE=path/to/startup.dmp \
      -S . -B build
cmake --build build
```

## Testing

### Test Infrastructure
- Test data files are **generated**, not committed (see `tests/.gitignore`)
- CI workflow creates test files before building
- Tests both configurations: with and without embedded files

### CI Workflow Changes
- Creates test files: `test_startup.dmp` and `test_user_data.dat`
- Builds once without embedded files (baseline)
- Rebuilds with embedded files
- Verifies sections and symbols in map file

### Manual Testing
```bash
# Create test files
mkdir -p tests/data
echo "DMOD Test Startup Package" > tests/data/test_startup.dmp
echo "Test User Data Content" > tests/data/test_user_data.dat

# Build with test files
cmake -DCMAKE_BUILD_TYPE=Debug \
      -DTARGET=STM32F746xG \
      -DSTARTUP_DMP_FILE=tests/data/test_startup.dmp \
      -DUSER_DATA_FILE=tests/data/test_user_data.dat \
      -S . -B build
cmake --build build

# Verify in map file
grep "__startup_dmp" build/dmboot.map
grep "__user_data" build/dmboot.map
```

## Design Decisions

1. **Helper script in separate file**: Keeps main CMakeLists.txt clean and allows code reuse
2. **Common logic**: Both file types use the same `embed_binary_file()` function
3. **Optional parameters**: Build works with or without files, no breaking changes
4. **Linker-based symbols**: Relies on linker script for symbol creation, not objcopy's default symbols
5. **Test files not committed**: Prevents binary bloat in repository, files created on-demand

## Files Changed
- `CMakeLists.txt` - Added build parameters and embed logic
- `scripts/embed_binary.cmake` - New helper script
- `linker/common.ld` - Added embedded data sections
- `src/main.c` - Added runtime loading logic
- `.github/workflows/build.yml` - Added test scenarios
- `README.md` - Added usage documentation
- `tests/README.md` - Added test documentation
- `tests/.gitignore` - Prevents test data files from being committed
