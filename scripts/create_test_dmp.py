#!/usr/bin/env python3
"""
Create a minimal test DMP (DMOD Package) file for testing purposes.

This creates an empty DMP package with valid header but no modules.
"""
import struct
import sys

DMOD_DMP_SIGNATURE = 0x444D5048  # 'DMPH'
DMOD_MAX_PACKAGE_NAME_LENGTH = 32

def create_test_dmp(output_path, package_name="test_pkg"):
    """Create a minimal valid DMP file"""
    
    # Ensure package name fits in the limit
    if len(package_name) >= DMOD_MAX_PACKAGE_NAME_LENGTH:
        package_name = package_name[:DMOD_MAX_PACKAGE_NAME_LENGTH-1]
    
    # Create package name as null-terminated string padded to DMOD_MAX_PACKAGE_NAME_LENGTH
    package_name_bytes = package_name.encode('utf-8') + b'\x00'
    package_name_bytes = package_name_bytes.ljust(DMOD_MAX_PACKAGE_NAME_LENGTH, b'\x00')
    
    # DMP Header structure:
    # uint32_t Signature       - 4 bytes
    # uint16_t HeaderSize      - 2 bytes
    # uint16_t HeaderVersion   - 2 bytes
    # char Name[32]            - 32 bytes
    # uint32_t MainIndex       - 4 bytes
    # uint32_t ModuleCount     - 4 bytes
    # Total: 48 bytes
    
    header_size = 48
    header_version = 0x0100  # Version 1.0
    main_index = 0xFFFFFFFF  # No main module
    module_count = 0         # No modules
    
    # Pack the header
    header = struct.pack(
        '<I H H 32s I I',
        DMOD_DMP_SIGNATURE,
        header_size,
        header_version,
        package_name_bytes,
        main_index,
        module_count
    )
    
    # Write to file
    with open(output_path, 'wb') as f:
        f.write(header)
    
    print(f"Created test DMP file: {output_path}")
    print(f"  Package name: {package_name}")
    print(f"  Header size: {header_size} bytes")
    print(f"  Module count: {module_count}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: create_test_dmp.py <output_file> [package_name]")
        sys.exit(1)
    
    output_file = sys.argv[1]
    package_name = sys.argv[2] if len(sys.argv) > 2 else "test_pkg"
    
    create_test_dmp(output_file, package_name)
