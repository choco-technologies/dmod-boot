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
    
    def __init__(self, map_file_path: str):
        self.map_file_path = map_file_path
        self.sections = {}
        self.symbols = {}
        self.object_contributions = defaultdict(lambda: {'text': 0, 'data': 0, 'bss': 0, 'rodata': 0})
        
    def parse(self):
        """Parse the map file"""
        with open(self.map_file_path, 'r') as f:
            content = f.read()
        
        # Parse main sections
        self._parse_sections(content)
        
        # Parse symbol definitions
        self._parse_symbols(content)
        
        # Parse object file contributions
        self._parse_object_contributions(content)
        
    def _parse_sections(self, content: str):
        """Parse section headers to get total sizes"""
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
        patterns = [
            r'^\s*(0x[0-9a-fA-F]+)\s+(__\w+__)\s*=',
            r'^\s*\[!provide\]\s+PROVIDE\s*\((\w+)\s*=\s*([^)]+)\)',
        ]
        
        for line in content.split('\n'):
            # First pattern
            match = re.match(patterns[0], line)
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
        """Extract library name from object file path"""
        if 'libdmlog' in object_path:
            return 'dmlog'
        elif 'libdmheap' in object_path:
            return 'dmheap'
        elif 'libdmod' in object_path:
            return 'DMOD Library'
        elif 'libdmboot_startup' in object_path:
            return 'startup'
        elif 'main.c.o' in object_path:
            return 'main'
        elif '/libc.a' in object_path or '/libgcc' in object_path:
            return 'libc/libgcc'
        else:
            return 'other'
    
    def aggregate_by_library(self) -> Dict[str, Dict[str, int]]:
        """Aggregate memory usage by library"""
        library_usage = defaultdict(lambda: {'text': 0, 'data': 0, 'bss': 0, 'rodata': 0})
        
        for obj_path, sections in self.object_contributions.items():
            lib_name = self.get_library_name(obj_path)
            for section, size in sections.items():
                library_usage[lib_name][section] += size
        
        return dict(library_usage)
    
    def get_rom_usage(self) -> Dict[str, int]:
        """Calculate ROM (Flash) usage"""
        rom_usage = {}
        
        # Get library contributions to text and rodata
        library_usage = self.aggregate_by_library()
        
        for lib_name, sections in library_usage.items():
            rom_usage[lib_name] = sections['text'] + sections['rodata']
        
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
    
    def get_total_rom(self) -> int:
        """Get total ROM usage"""
        total = 0
        if 'text' in self.sections:
            total += self.sections['text']['size']
        if 'rodata' in self.sections:
            total += self.sections['rodata']['size']
        if 'data' in self.sections:
            # .data is stored in ROM but copied to RAM
            total += self.sections['data']['size']
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


def format_size(size_bytes: int) -> str:
    """Format size in bytes to human-readable format"""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.2f} KB"
    else:
        return f"{size_bytes / (1024 * 1024):.2f} MB"


def print_memory_table(title: str, usage_dict: Dict[str, int], total: int, heap_size: int = 0):
    """Print a formatted memory usage table"""
    print(f"\n{'=' * 60}")
    print(f"{title:^60}")
    print(f"{'=' * 60}")
    print(f"{'Component':<30} {'Size':>15} {'%':>10}")
    print(f"{'-' * 60}")
    
    # Sort by size descending, but keep heap at the end if present
    items_without_heap = [(k, v) for k, v in usage_dict.items() if k != 'heap']
    sorted_items = sorted(items_without_heap, key=lambda x: x[1], reverse=True)
    
    for name, size in sorted_items:
        percentage = (size / total * 100) if total > 0 else 0
        print(f"{name:<30} {format_size(size):>15} {percentage:>9.1f}%")
    
    print(f"{'-' * 60}")
    print(f"{'Summary':<30} {format_size(total):>15} {'100.0%':>10}")
    
    # Show heap separately if provided
    if heap_size > 0:
        print(f"{'-' * 60}")
        print(f"{'heap (available)':<30} {format_size(heap_size):>15} {'':>10}")
    
    print(f"{'=' * 60}")


def generate_json_report(rom_usage: Dict[str, int], ram_usage: Dict[str, int], 
                        total_rom: int, total_ram: int, output_path: str):
    """Generate JSON report file"""
    report = {
        'rom': {
            'components': {k: v for k, v in rom_usage.items()},
            'total': total_rom
        },
        'ram': {
            'components': {k: v for k, v in ram_usage.items()},
            'total': total_ram
        }
    }
    
    # Ensure output directory exists
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"\nJSON report saved to: {output_path}")


def main():
    if len(sys.argv) < 2:
        print("Usage: memory_report.py <map_file> [output_dir]")
        sys.exit(1)
    
    map_file = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else str(Path(map_file).parent)
    
    if not Path(map_file).exists():
        print(f"Error: Map file not found: {map_file}")
        sys.exit(1)
    
    # Parse the map file
    parser = MemoryMapParser(map_file)
    parser.parse()
    
    # Get memory usage
    rom_usage = parser.get_rom_usage()
    ram_usage = parser.get_ram_usage()
    total_rom = parser.get_total_rom()
    total_ram = parser.get_total_ram()
    
    # Extract heap size for separate display
    heap_size = ram_usage.pop('heap', 0)
    
    # Print tables
    print_memory_table("ROM (Flash) Memory Usage", rom_usage, total_rom)
    print_memory_table("RAM Memory Usage", ram_usage, total_ram, heap_size)
    
    # Generate JSON report (include heap in JSON)
    ram_usage_with_heap = {**ram_usage, 'heap': heap_size}
    json_path = Path(output_dir) / "memory_report.json"
    generate_json_report(rom_usage, ram_usage_with_heap, total_rom, total_ram, str(json_path))


if __name__ == '__main__':
    main()
