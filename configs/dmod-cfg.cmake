# Use standard library
set(DMOD_USE_STDLIB OFF CACHE BOOL "Enable to use the standard library")

# Use getenv function
set(DMOD_USE_GETENV OFF CACHE BOOL "Enable to use the getenv function")

# Use stdio library
set(DMOD_USE_STDIO OFF CACHE BOOL "Enable to use the stdio library")

# Use assert function
set(DMOD_USE_ASSERT OFF CACHE BOOL "Enable to use the assert function")

# Use pthread library
set(DMOD_USE_PTHREAD OFF CACHE BOOL "Enable to use the pthread library")

# Use memory management functions
set(DMOD_USE_MMAN OFF CACHE BOOL "Enable to use memory management functions")

# Use aligned allocation
set(DMOD_USE_ALIGNED_ALLOC OFF CACHE BOOL "Enable to use aligned allocation")

# Use aligned malloc mock if aligned allocation is not available
set(DMOD_USE_ALIGNED_MALLOC_MOCK OFF CACHE BOOL "Enable to use aligned malloc mock if aligned allocation is not available")

# Use realloc function
set(DMOD_USE_REALLOC OFF CACHE BOOL "Enable to use the realloc function")

# Use FastLZ compression library
set(DMOD_USE_FASTLZ ON CACHE BOOL "Enable to use the FastLZ compression library")

# Implement custom printf 
set(DMOD_IMPLEMENT_PRINTF ON CACHE BOOL "Enable to implement printf function inside DMOD")

# Maximum number of modules
set(DMOD_MAX_MODULES 100 CACHE STRING "Maximum number of modules")

# Maximum number of required modules
set(DMOD_MAX_REQUIRED_MODULES 15 CACHE STRING "Maximum number of required modules")

# Mode of the system
set(DMOD_MODE "DMOD_SYSTEM" CACHE STRING "Mode of the system")

# Major version of your system
set(DMOD_SYSTEM_VERSION_MAJOR 0 CACHE STRING "Major version of your system")

# Minor version of your system
set(DMOD_SYSTEM_VERSION_MINOR 1 CACHE STRING "Minor version of your system")

# Build tests
set(DMOD_BUILD_TESTS OFF CACHE BOOL "Enable to build tests")

# Build examples
set(DMOD_BUILD_EXAMPLES OFF CACHE BOOL "Enable to build examples")

# Build tools
set(DMOD_BUILD_TOOLS OFF CACHE BOOL "Enable to build tools")

# Build templates
set(DMOD_BUILD_TEMPLATES OFF CACHE BOOL "Enable to build templates")

# Use exceptions
set(DMOD_USE_EXCEPTIONS OFF CACHE BOOL "Enable to use exceptions")

# Directory for DMFC files
set(DMOD_DMFC_DIR               "${CMAKE_BINARY_DIR}/dmfc"  CACHE STRING "Directory for DMFC files")

# Directory for DMF files
set(DMOD_DMF_DIR                "${CMAKE_BINARY_DIR}/dmf"   CACHE STRING "Directory for DMF files")

# Path to the default repository inside the system
set(DMOD_REPO_DIR               "${DMOD_DMF_DIR}" 			CACHE STRING "Directory for DMF files inside the system")

# Paths to the repositories inside the system in an array
set(DMOD_REPO_PATHS             "${DMOD_DMF_DIR}${DMOD_ARRAY_SEP}${DMOD_DMFC_DIR}"  CACHE STRING "Paths to the repositories inside the system in an array")    

# ===========================================================================
#                       BUILT-IN API
# ===========================================================================

# Allows for the built-in compression API (it can use a lot of flash memory and usually is not required - only decompression is required)
set(DMOD_BUILTIN_COMPRESSION_API ON CACHE BOOL "Enable to use the built-in compression API")