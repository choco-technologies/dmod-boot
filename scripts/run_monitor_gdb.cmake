# CMake script to run dmlog_monitor with GDB backend and the extracted ring buffer address
# This script is executed by the 'monitor-gdb' target

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
if(WIN32)
    set(DMLOG_MONITOR_EXECUTABLE "${PROJECT_SOURCE_DIR}/lib/dmlog/build_host/tools/monitor/dmlog_monitor.exe")
else()
    set(DMLOG_MONITOR_EXECUTABLE "${PROJECT_SOURCE_DIR}/lib/dmlog/build_host/tools/monitor/dmlog_monitor")
endif()

# Check if dmlog_monitor exists
if(NOT EXISTS ${DMLOG_MONITOR_EXECUTABLE})
    message(FATAL_ERROR "dmlog_monitor not found at ${DMLOG_MONITOR_EXECUTABLE}")
endif()

# Check if ring buffer address is defined
if(NOT DEFINED DMLOG_RING_BUFFER_ADDR)
    message(FATAL_ERROR "DMLOG_RING_BUFFER_ADDR not defined in dmlog_ring_buffer.cmake")
endif()

# Print information
message(STATUS "Starting dmlog_monitor in GDB mode...")
message(STATUS "Ring buffer address: ${DMLOG_RING_BUFFER_ADDR}")
message(STATUS "Ring buffer size: ${DMLOG_RING_BUFFER_SIZE}")
message(STATUS "Connecting to GDB server at localhost:3333 (OpenOCD GDB server)")

# Run dmlog_monitor with the extracted address in GDB mode
# Use execute_process without OUTPUT/ERROR capture so output goes directly to terminal
# OpenOCD's GDB server runs on port 3333 by default
execute_process(
    COMMAND ${DMLOG_MONITOR_EXECUTABLE} --gdb --port 3333 --addr ${DMLOG_RING_BUFFER_ADDR}
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
)

# Note: We intentionally don't check the exit code because:
# - dmlog_monitor returns non-zero when user presses Ctrl+C (expected)
# - dmlog_monitor returns non-zero when GDB server is not running (user can see the error message)
