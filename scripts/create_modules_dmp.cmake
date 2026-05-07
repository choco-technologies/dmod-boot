if(NOT DEFINED MODULES_DIR)
    message(FATAL_ERROR "MODULES_DIR is not defined")
endif()

if(NOT DEFINED OUTPUT_DMP)
    message(FATAL_ERROR "OUTPUT_DMP is not defined")
endif()

if(NOT DEFINED TODMP_EXECUTABLE)
    message(FATAL_ERROR "TODMP_EXECUTABLE is not defined")
endif()

if(NOT EXISTS "${MODULES_DIR}")
    file(MAKE_DIRECTORY "${MODULES_DIR}")
endif()

file(GLOB DMF_FILES "${MODULES_DIR}/*.dmf")

if(DMF_FILES)
    message(STATUS "Found DMF files in ${MODULES_DIR}:")
    foreach(DMF_FILE IN LISTS DMF_FILES)
        message(STATUS "  ${DMF_FILE}")
    endforeach()

    if(DEFINED MAIN_MODULE AND NOT MAIN_MODULE STREQUAL "")
        execute_process(
            COMMAND "${TODMP_EXECUTABLE}" modules "${MODULES_DIR}" "${OUTPUT_DMP}" "${MAIN_MODULE}"
            RESULT_VARIABLE TODMP_RESULT
        )
    else()
        execute_process(
            COMMAND "${TODMP_EXECUTABLE}" modules "${MODULES_DIR}" "${OUTPUT_DMP}"
            RESULT_VARIABLE TODMP_RESULT
        )
    endif()

    if(NOT TODMP_RESULT EQUAL 0)
        message(FATAL_ERROR "todmp failed while creating ${OUTPUT_DMP} (exit code: ${TODMP_RESULT})")
    endif()
else()
    if(FAIL_IF_EMPTY)
        message(FATAL_ERROR "No .dmf files found in ${MODULES_DIR} but main module '${MAIN_MODULE}' was expected. Module download may have failed.")
    endif()

    message(STATUS "No .dmf files found in ${MODULES_DIR}, creating empty modules.dmp placeholder")
    file(WRITE "${OUTPUT_DMP}" "")
endif()
