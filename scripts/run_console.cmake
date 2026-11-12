# CMake script of the 'console' target: a terminal program on the serial port of the board
#
# Inputs: DMBOOT_CONSOLE_PORT (auto: found with DMBOOT_CONSOLE_FIND), DMBOOT_CONSOLE_BAUD, DMBOOT_CONSOLE_TERMINAL (minicom, picocom, screen, miniterm; empty: the first found)

if(NOT DEFINED DMBOOT_CONSOLE_PORT OR "${DMBOOT_CONSOLE_PORT}" STREQUAL "")
    message(FATAL_ERROR "DMBOOT_CONSOLE_PORT not defined")
endif()
# auto: the port of the board, found by what its firmware tells (scripts/ymodem_send.py --print-port)
if("${DMBOOT_CONSOLE_PORT}" STREQUAL "auto")
    execute_process(COMMAND ${DMBOOT_CONSOLE_FIND} --port auto OUTPUT_VARIABLE found RESULT_VARIABLE found_result
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(NOT found_result EQUAL 0 OR "${found}" STREQUAL "")
        message(FATAL_ERROR "The port of the board was not found: give it with -DDMBOOT_CONSOLE_PORT=/dev/ttyACMx")
    endif()
    set(DMBOOT_CONSOLE_PORT "${found}")
endif()
if(NOT EXISTS "${DMBOOT_CONSOLE_PORT}")
    message(FATAL_ERROR "${DMBOOT_CONSOLE_PORT} does not exist: the board is not connected, or the port has another number (-DDMBOOT_ESP_PORT=...)")
endif()
if(NOT DEFINED DMBOOT_CONSOLE_BAUD OR "${DMBOOT_CONSOLE_BAUD}" STREQUAL "")
    set(DMBOOT_CONSOLE_BAUD 115200)
endif()

if("${DMBOOT_CONSOLE_TERMINAL}" STREQUAL "")
    set(candidates minicom picocom screen miniterm miniterm.py)
else()
    set(candidates ${DMBOOT_CONSOLE_TERMINAL})
endif()

set(terminal "")
foreach(candidate IN LISTS candidates)
    find_program(terminal_path NAMES ${candidate})
    if(terminal_path)
        set(terminal ${candidate})
        set(terminal_exe ${terminal_path})
        break()
    endif()
    unset(terminal_path CACHE)
endforeach()
if(terminal STREQUAL "")
    message(FATAL_ERROR "No terminal program found (tried: ${candidates}). Install minicom, picocom or screen, or pip install pyserial (miniterm)")
endif()

if(terminal STREQUAL "minicom")
    set(command ${terminal_exe} -o -D ${DMBOOT_CONSOLE_PORT} -b ${DMBOOT_CONSOLE_BAUD})   # -o: no modem initialization string
elseif(terminal STREQUAL "picocom")
    set(command ${terminal_exe} -b ${DMBOOT_CONSOLE_BAUD} ${DMBOOT_CONSOLE_PORT})
elseif(terminal STREQUAL "screen")
    set(command ${terminal_exe} ${DMBOOT_CONSOLE_PORT} ${DMBOOT_CONSOLE_BAUD})
else()
    set(command ${terminal_exe} ${DMBOOT_CONSOLE_PORT} ${DMBOOT_CONSOLE_BAUD})
endif()

message(STATUS "Console: ${command}")
execute_process(
    COMMAND ${command}
    INPUT_FILE /dev/stdin
    OUTPUT_FILE /dev/stdout
    ERROR_FILE /dev/stderr
)
