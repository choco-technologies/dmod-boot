# CMake script to run dmlog_monitor with the extracted ring buffer address
# This script is executed by the 'monitor' target

# Get the current build directory and source directory (passed from the parent CMake context)
if(NOT DEFINED PROJECT_BINARY_DIR)
    message(FATAL_ERROR "PROJECT_BINARY_DIR not defined")
endif()

if(NOT DEFINED PROJECT_SOURCE_DIR)
    message(FATAL_ERROR "PROJECT_SOURCE_DIR not defined")
endif()

# Include the ring buffer configuration
include(${PROJECT_BINARY_DIR}/dmlog_ring_buffer.cmake)

# Set paths
set(DMLOG_MONITOR_EXECUTABLE "${PROJECT_SOURCE_DIR}/lib/dmlog/build_host/tools/monitor/dmlog_monitor")

# Check if dmlog_monitor exists
if(NOT EXISTS ${DMLOG_MONITOR_EXECUTABLE})
    message(FATAL_ERROR "dmlog_monitor not found at ${DMLOG_MONITOR_EXECUTABLE}")
endif()

# Check if ring buffer address is defined
if(NOT DEFINED DMLOG_RING_BUFFER_ADDR)
    message(FATAL_ERROR "DMLOG_RING_BUFFER_ADDR not defined in dmlog_ring_buffer.cmake")
endif()

# Print information
message(STATUS "Starting dmlog_monitor...")
message(STATUS "Ring buffer address: ${DMLOG_RING_BUFFER_ADDR}")
message(STATUS "Ring buffer size: ${DMLOG_RING_BUFFER_SIZE}")

# Run dmlog_monitor with the extracted address
execute_process(
    COMMAND ${DMLOG_MONITOR_EXECUTABLE} --addr ${DMLOG_RING_BUFFER_ADDR}
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
    RESULT_VARIABLE RESULT
)

if(NOT RESULT EQUAL 0)
    message(FATAL_ERROR "dmlog_monitor exited with code ${RESULT}")
endif()
