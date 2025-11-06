# Memory Report Script

This directory contains the memory usage analysis script for DMOD Boot.

## memory_report.py

Analyzes linker map files and generates detailed memory usage reports showing RAM and ROM (Flash) usage broken down by libraries and components.

### Features

- Parses GCC ARM linker map files
- Generates formatted tables for ROM and RAM usage
- Creates JSON report for programmatic access
- Automatically integrated into the build process

### Usage

#### Automatic (CMake Integration)

The script runs automatically after building the project:

```bash
cd build
cmake ..
make
```

The memory report will be displayed after the build completes, and a JSON file will be created at `build/memory_report.json`.

#### Manual Execution

You can also run the script manually:

```bash
python3 scripts/memory_report.py <map_file> [output_dir]
```

**Arguments:**
- `map_file` - Path to the linker map file (e.g., `build/dmboot.map`)
- `output_dir` - Optional output directory for JSON file (defaults to map file directory)

**Example:**

```bash
python3 scripts/memory_report.py build/dmboot.map build/
```

### Output

The script generates:

1. **Console output** - Two formatted tables showing:
   - ROM (Flash) usage by component
   - RAM usage by component
   
2. **JSON file** - `memory_report.json` containing:
   ```json
   {
     "rom": {
       "components": { "library": size_in_bytes, ... },
       "total": total_rom_bytes
     },
     "ram": {
       "components": { "component": size_in_bytes, ... },
       "total": total_ram_bytes
     }
   }
   ```

### Components Tracked

The script tracks memory usage for:

- **Libraries**: DMOD Library, dmlog, dmheap
- **Standard libraries**: libc/libgcc
- **Special sections**: main stack, log buffer, heap (available space)
- **Application code**: main, startup
- **Other**: Remaining code and data

### Memory Regions

- **ROM (Flash)**: Contains code (.text) and constant data (.rodata)
- **RAM**: Contains initialized data (.data), uninitialized data (.bss), stack, log buffer, and heap
