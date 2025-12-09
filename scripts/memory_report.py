#!/usr/bin/env python3
"""
Memory Usage Report Generator for DMOD Boot

This script parses the linker map file and generates a detailed memory usage report
showing RAM and ROM (Flash) usage broken down by libraries and components.
"""

import sys
import re
import json
from pathlib import Path
from typing import Dict, List, Tuple
from collections import defaultdict


class MemoryMapParser:
    """Parser for GCC ARM linker map files"""
    
    def __init__(self, map_file_path: str, library_config: Dict[str, str] = None):
        self.map_file_path = map_file_path
        self.sections = {}
        self.symbols = {}
        self.object_contributions = defaultdict(lambda: {'text': 0, 'data': 0, 'bss': 0, 'rodata': 0})
        self.memory_regions = {}
        self.library_config = library_config or self._get_default_library_config()
    
    def _get_default_library_config(self) -> Dict[str, str]:
        """Get default library configuration with common patterns"""
        return {
            'libdmlog': 'dmlog',
            'libdmheap': 'dmheap',
            'libdmod': 'DMOD Library',
            'libdmboot_startup': 'startup',
            'main.c.o': 'main',
            '/libc.a': 'libc/libgcc',
            '/libgcc': 'libc/libgcc',
        }
        
    def parse(self):
        """Parse the map file"""
        with open(self.map_file_path, 'r') as f:
            content = f.read()
        
        # Parse memory configuration
        self._parse_memory_regions(content)
        
        # Parse main sections
        self._parse_sections(content)
        
        # Parse symbol definitions
        self._parse_symbols(content)
        
        # Parse object file contributions
        self._parse_object_contributions(content)
        
    def _parse_memory_regions(self, content: str):
        """Parse memory configuration section to get total memory sizes
        
        Matches lines like: rom  0x08000000  0x00100000  xr
        """
        in_memory_config = False
        
        for line in content.split('\n'):
            if 'Memory Configuration' in line:
                in_memory_config = True
                continue
            
            if in_memory_config:
                # End of memory configuration section
                if 'Linker script' in line:
                    break
                
                # Skip empty lines, header and separator lines
                if not line.strip() or 'Name' in line or 'Origin' in line or line.startswith('*default*'):
                    continue
                
                # Parse memory region line: rom  0x08000000  0x00100000  xr
                parts = line.split()
                if len(parts) >= 3:
                    try:
                        name = parts[0]
                        origin = int(parts[1], 16)
                        length = int(parts[2], 16)
                        self.memory_regions[name] = {
                            'origin': origin,
                            'length': length
                        }
                    except (ValueError, IndexError):
                        pass
    
    def _parse_sections(self, content: str):
        """Parse section headers to get total sizes
        
        Matches lines like: .text  0x08000000  0xefa0
        Also handles subsections like .text.startup by extracting the base section name.
        """
        # Pattern: .text           0x08000000     0xefa0
        pattern = r'^\.(\w+)\s+(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)'
        
        for line in content.split('\n'):
            match = re.match(pattern, line)
            if match:
                section_name = match.group(1)
                address = int(match.group(2), 16)
                size = int(match.group(3), 16)
                self.sections[section_name] = {
                    'address': address,
                    'size': size
                }
    
    def _parse_symbols(self, content: str):
        """Parse important symbols like stack, heap, logs"""
        # Pattern for symbols like: 0x00001000    __stack_size__ = 0x1000
        pattern = r'^\s*(0x[0-9a-fA-F]+)\s+(__\w+__)\s*='
        
        for line in content.split('\n'):
            match = re.match(pattern, line)
            if match:
                value = int(match.group(1), 16)
                name = match.group(2)
                self.symbols[name] = value
    def _parse_object_contributions(self, content: str):
        """Parse contributions from object files to each section"""
        # Pattern: .text  0x08000040  0x88  /path/to/file.o
        pattern = r'^\s*\.(\w+(?:\.\w+)?)\s+(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)\s+(.+)$'
        
        for line in content.split('\n'):
            match = re.match(pattern, line)
            if match:
                section = match.group(1).split('.')[0]  # Get base section name
                size = int(match.group(3), 16)
                object_file = match.group(4).strip()
                
                if size > 0 and section in ['text', 'data', 'bss', 'rodata']:
                    self.object_contributions[object_file][section] += size
    
    def get_library_name(self, object_path: str) -> str:
        """Extract library name from object file path using configuration"""
        # Check each pattern in the configuration
        for pattern, lib_name in self.library_config.items():
            if pattern in object_path:
                return lib_name
        
        # If no match found, return 'other'
        return 'other'
    
    def aggregate_by_library(self) -> Dict[str, Dict[str, int]]:
        """Aggregate memory usage by library"""
        library_usage = defaultdict(lambda: {'text': 0, 'data': 0, 'bss': 0, 'rodata': 0})
        
        for obj_path, sections in self.object_contributions.items():
            lib_name = self.get_library_name(obj_path)
            for section, size in sections.items():
                library_usage[lib_name][section] += size
        
        return dict(library_usage)
    
    def get_rom_usage(self, modules_dmp_size: int = 0) -> Dict[str, int]:
        """Calculate ROM (Flash) usage
        
        Args:
            modules_dmp_size: Size of modules.dmp file if it exists
        """
        rom_usage = {}
        
        # Get library contributions to text and rodata
        library_usage = self.aggregate_by_library()
        
        for lib_name, sections in library_usage.items():
            rom_usage[lib_name] = sections['text'] + sections['rodata']
        
        # Add modules.dmp size if provided
        if modules_dmp_size > 0:
            rom_usage['modules.dmp'] = modules_dmp_size
        
        return rom_usage
    
    def get_ram_usage(self) -> Dict[str, int]:
        """Calculate RAM usage"""
        ram_usage = {}
        
        # Get library contributions to data and bss
        library_usage = self.aggregate_by_library()
        
        for lib_name, sections in library_usage.items():
            ram_usage[lib_name] = sections['data'] + sections['bss']
        
        # Add special sections
        if '__stack_size__' in self.symbols:
            ram_usage['main stack'] = self.symbols['__stack_size__']
        
        if '__logs_size__' in self.symbols:
            ram_usage['log buffer'] = self.symbols['__logs_size__']
        
        # Calculate heap size
        if '__heap_start__' in self.symbols and '__heap_end__' in self.symbols:
            heap_size = self.symbols['__heap_end__'] - self.symbols['__heap_start__']
            ram_usage['heap'] = heap_size
        
        return ram_usage
    
    def get_total_rom(self, modules_dmp_size: int = 0) -> int:
        """Get total ROM usage
        
        Args:
            modules_dmp_size: Size of modules.dmp file if it exists
        """
        total = 0
        if 'text' in self.sections:
            total += self.sections['text']['size']
        if 'rodata' in self.sections:
            total += self.sections['rodata']['size']
        if 'data' in self.sections:
            # .data is stored in ROM but copied to RAM
            total += self.sections['data']['size']
        # Add modules.dmp size if provided
        total += modules_dmp_size
        return total
    
    def get_total_ram(self) -> int:
        """Get total RAM usage"""
        total = 0
        if 'data' in self.sections:
            total += self.sections['data']['size']
        if 'bss' in self.sections:
            total += self.sections['bss']['size']
        if 'stack' in self.sections:
            total += self.sections['stack']['size']
        if '__logs_size__' in self.symbols:
            total += self.symbols['__logs_size__']
        # Heap is available space, not used space, so don't include in total used
        return total
    
    def get_rom_capacity(self) -> int:
        """Get total ROM capacity from memory configuration"""
        if 'rom' in self.memory_regions:
            return self.memory_regions['rom']['length']
        return 0
    
    def get_ram_capacity(self) -> int:
        """Get total RAM capacity from memory configuration"""
        if 'ram' in self.memory_regions:
            return self.memory_regions['ram']['length']
        return 0


def format_size(size_bytes: int) -> str:
    """Format size in bytes to human-readable format"""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.2f} KB"
    else:
        return f"{size_bytes / (1024 * 1024):.2f} MB"


def print_memory_table(title: str, usage_dict: Dict[str, int], total_used: int, 
                       total_capacity: int = 0, heap_size: int = 0):
    """Print a formatted memory usage table
    
    Args:
        title: Table title
        usage_dict: Dictionary of component names and sizes
        total_used: Total memory used (for percentage calculations)
        total_capacity: Total memory capacity (if available)
        heap_size: Optional heap size to display separately (not included in percentages)
    """
    print(f"\n{'=' * 60}")
    print(f"{title:^60}")
    print(f"{'=' * 60}")
    print(f"{'Component':<30} {'Size':>15} {'%':>10}")
    print(f"{'-' * 60}")
    
    # Sort by size descending; heap should not be in usage_dict
    sorted_items = sorted(usage_dict.items(), key=lambda x: x[1], reverse=True)
    
    for name, size in sorted_items:
        percentage = (size / total_used * 100) if total_used > 0 else 0
        print(f"{name:<30} {format_size(size):>15} {percentage:>9.1f}%")
    
    print(f"{'-' * 60}")
    print(f"{'Used':<30} {format_size(total_used):>15} {'100.0%':>10}")
    
    # Show heap separately as available space, not used space
    if heap_size > 0:
        print(f"{'-' * 60}")
        print(f"{'heap (available)':<30} {format_size(heap_size):>15} {'':>10}")
    
    # Show total capacity and free memory if available
    if total_capacity > 0:
        free_memory = total_capacity - total_used
        usage_percentage = (total_used / total_capacity * 100) if total_capacity > 0 else 0
        print(f"{'=' * 60}")
        print(f"{'Total Capacity':<30} {format_size(total_capacity):>15} {'':>10}")
        print(f"{'Free':<30} {format_size(free_memory):>15} {(100 - usage_percentage):>9.1f}%")
        print(f"{'Overall Usage':<30} {format_size(total_used):>15} {usage_percentage:>9.1f}%")
    
    print(f"{'=' * 60}")


def generate_json_report(rom_usage: Dict[str, int], ram_usage: Dict[str, int], 
                        total_rom_used: int, total_ram_used: int,
                        rom_capacity: int, ram_capacity: int, output_path: str):
    """Generate JSON report file"""
    report = {
        'rom': {
            'components': {k: v for k, v in rom_usage.items()},
            'used': total_rom_used,
            'capacity': rom_capacity,
            'free': rom_capacity - total_rom_used if rom_capacity > 0 else 0,
            'usage_percent': (total_rom_used / rom_capacity * 100) if rom_capacity > 0 else 0
        },
        'ram': {
            'components': {k: v for k, v in ram_usage.items()},
            'used': total_ram_used,
            'capacity': ram_capacity,
            'free': ram_capacity - total_ram_used if ram_capacity > 0 else 0,
            'usage_percent': (total_ram_used / ram_capacity * 100) if ram_capacity > 0 else 0
        }
    }
    
    # Ensure output directory exists
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"\nJSON report saved to: {output_path}")


def load_library_config(config_path: str = None, auto_detect_dir: str = None) -> Dict[str, str]:
    """Load library configuration from JSON file or auto-detect from directory
    
    Args:
        config_path: Path to JSON configuration file
        auto_detect_dir: Directory to auto-detect libraries from (e.g., 'lib/')
    
    Returns:
        Dictionary mapping library patterns to display names
    """
    config = {}
    
    # Load from JSON file if provided
    if config_path and Path(config_path).exists():
        with open(config_path, 'r') as f:
            config = json.load(f)
    
    # Auto-detect libraries from directory
    if auto_detect_dir and Path(auto_detect_dir).exists():
        lib_dir = Path(auto_detect_dir)
        for item in lib_dir.iterdir():
            if item.is_dir():
                lib_name = item.name
                # Add library pattern mapping
                pattern = f'lib{lib_name}'
                if pattern not in config:
                    config[pattern] = lib_name
    
    return config


def main():
    if len(sys.argv) < 2:
        print("Usage: memory_report.py <map_file> [output_dir] [--lib-config <config.json>] [--lib-dir <lib_directory>]")
        sys.exit(1)
    
    map_file = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else str(Path(map_file).parent)
    
    # Parse optional arguments
    config_file = None
    lib_dir = None
    
    i = 2 if not sys.argv[2].startswith('--') else 1
    while i < len(sys.argv) - 1:
        if sys.argv[i] == '--lib-config':
            config_file = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--lib-dir':
            lib_dir = sys.argv[i + 1]
            i += 2
        else:
            i += 1
    
    if not Path(map_file).exists():
        print(f"Error: Map file not found: {map_file}")
        sys.exit(1)
    
    # Load library configuration
    library_config = load_library_config(config_file, lib_dir)
    
    # Parse the map file
    parser = MemoryMapParser(map_file, library_config if library_config else None)
    parser.parse()
    
    # Check for modules.dmp file in the output directory (build directory)
    modules_dmp_path = Path(output_dir) / "modules.dmp"
    modules_dmp_size = 0
    if modules_dmp_path.exists():
        modules_dmp_size = modules_dmp_path.stat().st_size
        print(f"Found modules.dmp: {format_size(modules_dmp_size)}")
    
    # Get memory usage
    rom_usage = parser.get_rom_usage(modules_dmp_size)
    ram_usage = parser.get_ram_usage()
    total_rom_used = parser.get_total_rom(modules_dmp_size)
    total_ram_used = parser.get_total_ram()
    
    # Get memory capacities
    rom_capacity = parser.get_rom_capacity()
    ram_capacity = parser.get_ram_capacity()
    
    # Extract heap size for separate display
    heap_size = ram_usage.pop('heap', 0)
    
    # Print tables
    print_memory_table("ROM (Flash) Memory Usage", rom_usage, total_rom_used, rom_capacity)
    print_memory_table("RAM Memory Usage", ram_usage, total_ram_used, ram_capacity, heap_size)
    
    # Generate JSON report (include heap in JSON)
    ram_usage_with_heap = {**ram_usage, 'heap': heap_size}
    json_path = Path(output_dir) / "memory_report.json"
    generate_json_report(rom_usage, ram_usage_with_heap, total_rom_used, total_ram_used,
                        rom_capacity, ram_capacity, str(json_path))


if __name__ == '__main__':
    main()
