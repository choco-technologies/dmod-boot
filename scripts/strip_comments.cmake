# Copies a directory tree and strips the comments from its configuration files (*.ini, *.rules)
#
# Usage:
#   cmake -DSRC=<source dir> -DDST=<destination dir> -P strip_comments.cmake
#
# Removed: the lines that start with ';' or '#' (leading blanks allowed) and the empty lines. The comments after a
# value are left alone - dmini cuts them by itself, but they are not worth the risk of cutting a value. Every other
# file is copied as it is. <destination dir> is made anew.

if(NOT DEFINED SRC OR NOT DEFINED DST)
    message(FATAL_ERROR "strip_comments.cmake: SRC and DST are required")
endif()

file(REMOVE_RECURSE "${DST}")
file(MAKE_DIRECTORY "${DST}")

file(GLOB_RECURSE files RELATIVE "${SRC}" LIST_DIRECTORIES false "${SRC}/*")
foreach(file IN LISTS files)
    get_filename_component(dir "${file}" DIRECTORY)
    file(MAKE_DIRECTORY "${DST}/${dir}")

    if(file MATCHES "\\.(ini|rules)$")
        file(READ "${SRC}/${file}" content)
        # "\n" in front makes the first line a line like the others
        set(content "\n${content}")
        string(REGEX REPLACE "\n[ \t\r]*[;#][^\n]*" "" content "${content}")
        # The matches do not overlap: "\n\n\n" becomes "\n\n" in one go
        set(previous "")
        while(NOT content STREQUAL previous)
            set(previous "${content}")
            string(REGEX REPLACE "\n[ \t\r]*\n" "\n" content "${content}")
        endwhile()
        string(SUBSTRING "${content}" 1 -1 content)
        file(WRITE "${DST}/${file}" "${content}")
    else()
        file(COPY "${SRC}/${file}" DESTINATION "${DST}/${dir}")
    endif()
endforeach()
