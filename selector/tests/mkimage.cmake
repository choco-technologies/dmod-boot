# ctest: make an image with the tool and let the test of the core verify it
execute_process(COMMAND ${PY} ${TOOL} ${IN} ${OUT} --version 7 --capacity 0x60000 RESULT_VARIABLE r)
if(NOT r EQUAL 0)
    message(FATAL_ERROR "dmsel_mkimage.py failed")
endif()
execute_process(COMMAND ${CHECK} ${OUT} RESULT_VARIABLE r)
if(NOT r EQUAL 0)
    message(FATAL_ERROR "the core does not accept the image of the tool")
endif()
