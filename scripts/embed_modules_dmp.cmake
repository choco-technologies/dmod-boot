if(NOT DEFINED INPUT_DMP)
    message(FATAL_ERROR "INPUT_DMP is not defined")
endif()

if(NOT DEFINED OUTPUT_OBJECT)
    message(FATAL_ERROR "OUTPUT_OBJECT is not defined")
endif()

if(NOT DEFINED OBJCOPY_EXECUTABLE)
    message(FATAL_ERROR "OBJCOPY_EXECUTABLE is not defined")
endif()

set(EMBED_SOURCE_FILE "${INPUT_DMP}")
if(EXISTS "${INPUT_DMP}")
    message(STATUS "Embedding modules.dmp from ${INPUT_DMP}")
else()
    set(EMBED_SOURCE_FILE "${CMAKE_BINARY_DIR}/empty_modules_dmp.bin")
    file(WRITE "${EMBED_SOURCE_FILE}" "")
    message(STATUS "No modules.dmp found, embedding empty placeholder")
endif()

execute_process(
    COMMAND "${OBJCOPY_EXECUTABLE}"
        --input-target=binary
        --output-target=elf32-littlearm
        --binary-architecture=arm
        --rename-section .data=.embedded.modules_dmp,alloc,load,readonly,data,contents
        "${EMBED_SOURCE_FILE}"
        "${OUTPUT_OBJECT}"
    RESULT_VARIABLE OBJCOPY_RESULT
)

if(NOT OBJCOPY_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to create embedded modules object (objcopy exit code: ${OBJCOPY_RESULT})")
endif()
