#================================================================================================================================
# 	Default tools configuration for Cortex-M4
#================================================================================================================================

#
#   Default configuration options
#
set(DMOD_USE_STDLIB 	        OFF )
set(DMOD_USE_STDIO  	        OFF )
set(DMOD_USE_ASSERT 	        OFF )
set(DMOD_USE_PTHREAD            OFF )
set(DMOD_USE_MMAN   	        OFF )
set(DMOD_BUILD_TESTS            OFF )
set(DMOD_BUILD_EXAMPLES         OFF )
set(DMOD_BUILD_TOOLS            OFF )

#
#	Toolchain configuration
#
if(NOT DEFINED COMPILER_PATH)
	set(COMPILER_PATH "")
endif()
if(NOT DEFINED CROSS_COMPILE)
	set(CROSS_COMPILE "arm-none-eabi-")
endif()
if(NOT DEFINED CPUCONFIG_CFLAGS)
	set(CPUCONFIG_CFLAGS "-mcpu=cortex-m4 -mthumb -mno-unaligned-access -DGCC_ARMCM4 -mpic-data-is-text-relative")
endif()
if(NOT DEFINED CPUCONFIG_CXXFLAGS)
	set(CPUCONFIG_CXXFLAGS "-mcpu=cortex-m4 -mthumb -mno-unaligned-access -DGCC_ARMCM4 -mpic-data-is-text-relative")
endif()
set(CMAKE_C_COMPILER "${CROSS_COMPILE}gcc")
set(CMAKE_CXX_COMPILER "${CROSS_COMPILE}g++")
set(CMAKE_LINKER "${CROSS_COMPILE}ld")
set(CMAKE_OBJDUMP "${CROSS_COMPILE}objdump")
set(CMAKE_OBJCOPY "${CROSS_COMPILE}objcopy")
set(CMAKE_AR "${CROSS_COMPILE}ar")
set(MAKE "make")
set(MKDIR "mkdir")
set(RM "rm")
set(CMAKE_C_FLAGS "-Wall -std=c11 ${CPUCONFIG_CFLAGS}")
set(CMAKE_CXX_FLAGS "-Wall -std=c++17 ${CPUCONFIG_CXXFLAGS}")
set(CMAKE_LFLAGS "${CPUCONFIG_LDFLAGS}")
