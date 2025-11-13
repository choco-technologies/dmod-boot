# =====================================================================
#               Binary File Embedding Helper Script
# =====================================================================
# This script provides functions to embed binary files into ROM sections
# and make them accessible at runtime through linker symbols.
#
# Usage:
#   include(scripts/embed_binary.cmake)
#   embed_binary_file(
#       INPUT_FILE path/to/file.bin
#       SECTION_NAME ".startup_dmp"
#       SYMBOL_PREFIX "__startup_dmp"
#   )
#
# This creates:
#   - A .o object file with the binary data in the specified section
#   - Linker symbols: ${SYMBOL_PREFIX}_start, ${SYMBOL_PREFIX}_end, ${SYMBOL_PREFIX}_size
# =====================================================================

# Function to convert a binary file into an object file with linker symbols
function(embed_binary_file)
    # Parse arguments
    set(options "")
    set(oneValueArgs INPUT_FILE SECTION_NAME SYMBOL_PREFIX OUTPUT_OBJECT)
    set(multiValueArgs "")
    cmake_parse_arguments(EMBED "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Validate required arguments
    if(NOT DEFINED EMBED_INPUT_FILE)
        message(FATAL_ERROR "embed_binary_file: INPUT_FILE is required")
    endif()
    
    if(NOT DEFINED EMBED_SECTION_NAME)
        message(FATAL_ERROR "embed_binary_file: SECTION_NAME is required")
    endif()
    
    if(NOT DEFINED EMBED_SYMBOL_PREFIX)
        message(FATAL_ERROR "embed_binary_file: SYMBOL_PREFIX is required")
    endif()

    if(NOT DEFINED EMBED_OUTPUT_OBJECT)
        set(EMBED_OUTPUT_OBJECT "${CMAKE_BINARY_DIR}/${EMBED_SYMBOL_PREFIX}.o")
    endif()

    # Check if input file exists
    if(NOT EXISTS "${EMBED_INPUT_FILE}")
        message(FATAL_ERROR "embed_binary_file: Input file '${EMBED_INPUT_FILE}' does not exist")
    endif()

    # Get absolute path
    get_filename_component(EMBED_INPUT_FILE_ABS "${EMBED_INPUT_FILE}" ABSOLUTE)

    # Create a linker script that embeds the binary
    set(EMBED_LINKER_SCRIPT "${CMAKE_BINARY_DIR}/${EMBED_SYMBOL_PREFIX}_embed.ld")
    
    file(WRITE "${EMBED_LINKER_SCRIPT}"
"SECTIONS
{
    ${EMBED_SECTION_NAME} :
    {
        ${EMBED_SYMBOL_PREFIX}_start = .;
        PROVIDE(${EMBED_SYMBOL_PREFIX}_start = .);
        KEEP(*(.embedded_data))
        ${EMBED_SYMBOL_PREFIX}_end = .;
        PROVIDE(${EMBED_SYMBOL_PREFIX}_end = .);
        ${EMBED_SYMBOL_PREFIX}_size = ${EMBED_SYMBOL_PREFIX}_end - ${EMBED_SYMBOL_PREFIX}_start;
        PROVIDE(${EMBED_SYMBOL_PREFIX}_size = ${EMBED_SYMBOL_PREFIX}_end - ${EMBED_SYMBOL_PREFIX}_start);
    }
}
")

    # Create object file using objcopy
    # This converts the binary file into an ELF object with the data in a section
    add_custom_command(
        OUTPUT "${EMBED_OUTPUT_OBJECT}"
        COMMAND ${CMAKE_OBJCOPY}
            --input-target=binary
            --output-target=elf32-littlearm
            --binary-architecture=arm
            --rename-section .data=${EMBED_SECTION_NAME},alloc,load,readonly,data,contents
            "${EMBED_INPUT_FILE_ABS}"
            "${EMBED_OUTPUT_OBJECT}"
        DEPENDS "${EMBED_INPUT_FILE_ABS}"
        COMMENT "Embedding ${EMBED_INPUT_FILE} into section ${EMBED_SECTION_NAME}"
        VERBATIM
    )

    # Set output variable in parent scope
    set(${EMBED_OUTPUT_OBJECT} "${EMBED_OUTPUT_OBJECT}" PARENT_SCOPE)
    
    message(STATUS "Will embed '${EMBED_INPUT_FILE}' as '${EMBED_SECTION_NAME}' section with symbols '${EMBED_SYMBOL_PREFIX}_*'")
endfunction()

# Helper function to get file size
function(get_file_size FILE_PATH OUT_VAR)
    if(EXISTS "${FILE_PATH}")
        file(SIZE "${FILE_PATH}" FILE_SIZE)
        set(${OUT_VAR} ${FILE_SIZE} PARENT_SCOPE)
    else()
        set(${OUT_VAR} 0 PARENT_SCOPE)
    endif()
endfunction()
