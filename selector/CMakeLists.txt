# The selector: portable code (src/), the flash in RAM for its tests (port/host/)
# Standalone: cmake -S selector -B build-selector && cmake --build build-selector && ctest --test-dir build-selector
cmake_minimum_required(VERSION 3.16)
project(dmsel LANGUAGES C)
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
option(DMSEL_SANITIZE "AddressSanitizer + UBSanitizer" OFF)

add_library(dmsel STATIC src/dmsel.c)
target_include_directories(dmsel PUBLIC include)
target_compile_options(dmsel PRIVATE -Wall -Wextra -Wshadow -Wpedantic -Werror)

enable_testing()
add_executable(test_selector tests/test_selector.c port/host/dmsel_port_host.c)
target_include_directories(test_selector PRIVATE port/host)
target_link_libraries(test_selector PRIVATE dmsel)
target_compile_options(test_selector PRIVATE -Wall -Wextra)
if(DMSEL_SANITIZE)
    foreach(t dmsel test_selector)
        target_compile_options(${t} PRIVATE -fsanitize=address,undefined -fno-sanitize-recover=undefined)
        target_link_options(${t} PRIVATE -fsanitize=address,undefined)
    endforeach()
endif()
add_test(NAME test_selector COMMAND test_selector)

# The tool that makes the images (python) and the core have to agree on the header and on the CRC
find_package(Python3 COMPONENTS Interpreter)
if(Python3_FOUND)
    file(WRITE ${CMAKE_BINARY_DIR}/code.bin "vectors and code of a test image - 0123456789")
    add_test(NAME mkimage COMMAND ${CMAKE_COMMAND}
        -DPY=${Python3_EXECUTABLE} -DTOOL=${CMAKE_CURRENT_SOURCE_DIR}/tools/dmsel_mkimage.py
        -DIN=${CMAKE_BINARY_DIR}/code.bin -DOUT=${CMAKE_BINARY_DIR}/image.bin -DCHECK=$<TARGET_FILE:test_selector>
        -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/mkimage.cmake)
endif()
