# DMOD configuration for dmod-boot (embedded STM32 project)

ifeq ($(ON),)
	ON=1
endif
ifeq ($(OFF),)
	OFF=0
endif

# Disable standard library features not available on bare-metal
DMOD_USE_STDLIB=OFF
DMOD_USE_GETENV=OFF
DMOD_USE_STDIO=OFF
DMOD_USE_ASSERT=OFF
DMOD_USE_PTHREAD=OFF
DMOD_USE_MMAN=OFF

# Memory allocation settings - dmheap will provide these
DMOD_USE_ALIGNED_ALLOC=ON
DMOD_USE_ALIGNED_MALLOC_MOCK=OFF
DMOD_USE_REALLOC=ON

# Compression - enable for module support
DMOD_USE_FASTLZ=ON

# Module limits for embedded system
DMOD_MAX_MODULES=10
DMOD_MAX_REQUIRED_MODULES=5

# Mode of the system
DMOD_MODE="DMOD_SYSTEM"

# System version
DMOD_SYSTEM_VERSION_MAJOR=0
DMOD_SYSTEM_VERSION_MINOR=1

# Build options - disable for embedded targets
DMOD_BUILD_TESTS=OFF
DMOD_BUILD_EXAMPLES=OFF
DMOD_BUILD_TOOLS=OFF
DMOD_BUILD_TEMPLATES=OFF

# Exceptions not supported in embedded
DMOD_USE_EXCEPTIONS=OFF

# Directory for DMFC files
DMOD_DMFC_DIR=${DMOD_BUILD_DIR}/dmfc

# Directory for DMF files
DMOD_DMF_DIR=${DMOD_BUILD_DIR}/dmf

# Path to the default repository inside the system
DMOD_REPO_DIR=${DMOD_DMF_DIR}

# Paths to the repositories inside the system in an array
DMOD_REPO_PATHS=${DMOD_DMF_DIR}${DMOD_ARRAY_SEP}${DMOD_DMFC_DIR}

# Target CPU - ARM Cortex-M
DMOD_CPU_NAME="arm"

# Tools configuration for ARM embedded
DMOD_TOOLS_NAME="arch/arm"
