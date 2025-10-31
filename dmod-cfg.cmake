# DMOD configuration for dmod-boot (embedded STM32 project)

# Disable standard library features not available on bare-metal
set(DMOD_USE_STDLIB OFF CACHE BOOL "Enable to use the standard library")
set(DMOD_USE_GETENV OFF CACHE BOOL "Enable to use the getenv function")
set(DMOD_USE_STDIO OFF CACHE BOOL "Enable to use the stdio library")
set(DMOD_USE_ASSERT OFF CACHE BOOL "Enable to use the assert function")
set(DMOD_USE_PTHREAD OFF CACHE BOOL "Enable to use the pthread library")
set(DMOD_USE_MMAN OFF CACHE BOOL "Enable to use memory management functions")

# Memory allocation settings - dmheap will provide these
set(DMOD_USE_ALIGNED_ALLOC ON CACHE BOOL "Enable to use aligned allocation")
set(DMOD_USE_ALIGNED_MALLOC_MOCK OFF CACHE BOOL "Enable to use aligned malloc mock if aligned allocation is not available")
set(DMOD_USE_REALLOC ON CACHE BOOL "Enable to use the realloc function")

# Compression - enable for module support
set(DMOD_USE_FASTLZ ON CACHE BOOL "Enable to use the FastLZ compression library")

# Module limits for embedded system
set(DMOD_MAX_MODULES 10 CACHE STRING "Maximum number of modules")
set(DMOD_MAX_REQUIRED_MODULES 5 CACHE STRING "Maximum number of required modules")

# Mode of the system
set(DMOD_MODE "DMOD_SYSTEM" CACHE STRING "Mode of the system")

# System version
set(DMOD_SYSTEM_VERSION_MAJOR 0 CACHE STRING "Major version of your system")
set(DMOD_SYSTEM_VERSION_MINOR 1 CACHE STRING "Minor version of your system")

# Build options - disable for embedded targets
set(DMOD_BUILD_TESTS OFF CACHE BOOL "Enable to build tests")
set(DMOD_BUILD_EXAMPLES OFF CACHE BOOL "Enable to build examples")
set(DMOD_BUILD_TOOLS OFF CACHE BOOL "Enable to build tools")
set(DMOD_BUILD_TEMPLATES OFF CACHE BOOL "Enable to build templates")

# Exceptions not supported in embedded
set(DMOD_USE_EXCEPTIONS OFF CACHE BOOL "Enable to use exceptions")

# Directory for DMFC files
set(DMOD_DMFC_DIR "${CMAKE_CURRENT_BINARY_DIR}/dmfc" CACHE STRING "Directory for DMFC files")

# Directory for DMF files
set(DMOD_DMF_DIR "${CMAKE_CURRENT_BINARY_DIR}/dmf" CACHE STRING "Directory for DMF files")

# Path to the default repository inside the system
set(DMOD_REPO_DIR "${DMOD_DMF_DIR}" CACHE STRING "Directory for DMF files inside the system")

# Paths to the repositories inside the system in an array
set(DMOD_REPO_PATHS "${DMOD_DMF_DIR}${DMOD_ARRAY_SEP}${DMOD_DMFC_DIR}" CACHE STRING "Paths to the repositories inside the system in an array")

# Target CPU - ARM Cortex-M
set(DMOD_CPU_NAME "arm" CACHE STRING "Name of the target cpu, if empty, the target is generic")

# Tools configuration for ARM embedded
set(DMOD_TOOLS_NAME "arch/arm" CACHE STRING "Name of the tools configuration")

# Built-in API
set(DMOD_BUILTIN_COMPRESSION_API OFF CACHE BOOL "Disable compression API to save flash memory")
