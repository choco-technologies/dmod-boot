#!/usr/bin/env python3
"""
Extract dmlog ring buffer address from the map file.
This script parses the .map file to find __logs_start__ and __logs_size__ symbols.
"""

import re
import sys
import argparse


def extract_ring_buffer_info(map_file_path):
    """Extract ring buffer address and size from map file."""
    logs_start = None
    logs_size = None
    
    with open(map_file_path, 'r') as f:
        content = f.read()
        
        # Look for __logs_start__ address
        match = re.search(r'^\s*(0x[0-9a-fA-F]+)\s+__logs_start__\s*=', content, re.MULTILINE)
        if match:
            logs_start = match.group(1)
        
        # Look for __logs_size__ value
        match = re.search(r'^\s*(0x[0-9a-fA-F]+)\s+__logs_size__\s*=', content, re.MULTILINE)
        if match:
            logs_size = match.group(1)
    
    return logs_start, logs_size


def main():
    parser = argparse.ArgumentParser(description='Extract dmlog ring buffer address from map file')
    parser.add_argument('map_file', help='Path to the .map file')
    parser.add_argument('--output', help='Output file path (if not specified, prints to stdout)')
    parser.add_argument('--format', choices=['txt', 'cmake'], default='txt',
                        help='Output format (txt or cmake)')
    
    args = parser.parse_args()
    
    logs_start, logs_size = extract_ring_buffer_info(args.map_file)
    
    if not logs_start:
        print(f"Error: Could not find __logs_start__ in {args.map_file}", file=sys.stderr)
        sys.exit(1)
    
    if not logs_size:
        print(f"Error: Could not find __logs_size__ in {args.map_file}", file=sys.stderr)
        sys.exit(1)
    
    # Generate output based on format
    if args.format == 'cmake':
        output = f"# Ring buffer configuration (auto-generated)\n"
        output += f"set(DMLOG_RING_BUFFER_ADDR \"{logs_start}\")\n"
        output += f"set(DMLOG_RING_BUFFER_SIZE \"{logs_size}\")\n"
    else:
        output = f"{logs_start}\n"
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(output)
        print(f"Ring buffer info written to {args.output}")
    else:
        print(output, end='')
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
