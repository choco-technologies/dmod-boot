# Memory Report Script

This directory contains the memory usage analysis script for DMOD Boot.

## memory_report.py

Analyzes linker map files and generates detailed memory usage reports showing RAM and ROM (Flash) usage broken down by libraries and components.

### Features

- Parses GCC ARM linker map files
- Generates formatted tables for ROM and RAM usage
- Creates JSON report for programmatic access
- Automatically integrated into the build process
- **Configurable library detection** - Auto-detects libraries or uses custom configuration

### Usage

#### Automatic (CMake Integration)

The script runs automatically after building the project with auto-detection of libraries in the `lib/` directory:

```bash
cd build
cmake ..
make
```

The memory report will be displayed after the build completes, and a JSON file will be created at `build/memory_report.json`.

#### Manual Execution

You can also run the script manually:

```bash
python3 scripts/memory_report.py <map_file> [output_dir] [--lib-config <config.json>] [--lib-dir <lib_directory>]
```

**Arguments:**
- `map_file` - Path to the linker map file (e.g., `build/dmboot.map`)
- `output_dir` - Optional output directory for JSON file (defaults to map file directory)
- `--lib-config <config.json>` - Optional JSON configuration file for library mapping
- `--lib-dir <lib_directory>` - Optional directory to auto-detect libraries from (e.g., `lib/`)

**Examples:**

Basic usage:
```bash
python3 scripts/memory_report.py build/dmboot.map build/
```

With auto-detection from lib directory:
```bash
python3 scripts/memory_report.py build/dmboot.map build/ --lib-dir lib/
```

With custom configuration file:
```bash
python3 scripts/memory_report.py build/dmboot.map build/ --lib-config scripts/library_config.json
```

### Library Configuration

#### Auto-Detection

When you use `--lib-dir` option, the script automatically detects libraries in the specified directory. For example, if you have `lib/dmlog/`, `lib/dmheap/`, and `lib/dmod/`, the script will automatically map:
- `libdmlog` → `dmlog`
- `libdmheap` → `dmheap`
- `libdmod` → `dmod`

This means when you add new libraries to the `lib/` directory, they will be automatically detected and included in the memory report.

#### Custom Configuration File

You can create a JSON configuration file to define custom library mappings. See `library_config.json.example` for an example:

```json
{
  "libdmlog": "dmlog",
  "libdmheap": "dmheap",
  "libdmod": "DMOD Library",
  "libdmboot_startup": "startup",
  "main.c.o": "main",
  "/libc.a": "libc/libgcc",
  "/libgcc": "libc/libgcc"
}
```

The keys are patterns to match in the object file paths, and the values are the display names in the report.

### Output

The script generates:

1. **Console output** - Two formatted tables showing:
   - ROM (Flash) usage by component with capacity and free memory
   - RAM usage by component with capacity and free memory
   
2. **JSON file** - `memory_report.json` containing:
   ```json
   {
     "rom": {
       "components": { "library": size_in_bytes, ... },
       "used": used_bytes,
       "capacity": total_capacity_bytes,
       "free": free_bytes,
       "usage_percent": percentage
     },
     "ram": {
       "components": { "component": size_in_bytes, ... },
       "used": used_bytes,
       "capacity": total_capacity_bytes,
       "free": free_bytes,
       "usage_percent": percentage
     }
   }
   ```

### Components Tracked

The script tracks memory usage for:

- **Libraries**: Automatically detected from `lib/` directory or configured via JSON
- **Standard libraries**: libc/libgcc
- **Special sections**: main stack, log buffer, heap (available space)
- **Application code**: main, startup
- **Other**: Remaining code and data

### Memory Regions

- **ROM (Flash)**: Contains code (.text) and constant data (.rodata)
- **RAM**: Contains initialized data (.data), uninitialized data (.bss), stack, log buffer, and heap
