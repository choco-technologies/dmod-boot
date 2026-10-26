# Splash logo - shown by the display driver (dmlcdtft) as soon as the display
# is up, in the middle of a screen filled with its clear_color.
#
#   - DMBOOT_SPLASH_LOGO       asset picked by the board (assets/splash/<name>.dmvi)
#                              or a path to a .dmvi file; empty: no logo
#   - DMBOOT_SPLASH_LOGO_PATH  where the driver finds the logo on the target -
#                              dmod-boot sets $SPLASH_LOGO to it at boot
#
# A logo under /eviews/ is built into the embedded views filesystem: the .dmvi
# is unpacked into a .dmvir (scripts/dmvi_to_dmvir.py) - the raw pixels the
# driver draws without decoding anything - and placed at the same path under
# DMBOOT_EVIEWS_DIR. Sets DMBOOT_SPLASH_LOGO_FILE to that file (for the
# eviews image to depend on), empty when nothing is built.
#
# A logo under the mount point of the external flash (DMBOOT_EXT_MOUNT, e.g.
# /ext/views/splash_logo.dmvir) stays out of the firmware: it is unpacked into
# build/ext, which upload-ext sends to the flash chip. The display driver
# (an ext module then) shows it once /ext is mounted.

set(DMBOOT_SPLASH_ASSETS_DIR "${CMAKE_SOURCE_DIR}/assets/splash")
set(DMBOOT_SPLASH_LOGO_FILE "")

set(_SPLASH_EVIEWS_PREFIX "/eviews/")
string(LENGTH "${_SPLASH_EVIEWS_PREFIX}" _SPLASH_EVIEWS_PREFIX_LENGTH)
string(FIND "${DMBOOT_SPLASH_LOGO_PATH}" "${_SPLASH_EVIEWS_PREFIX}" _SPLASH_PREFIX_AT)
if(_SPLASH_PREFIX_AT EQUAL 0)
    string(SUBSTRING "${DMBOOT_SPLASH_LOGO_PATH}" ${_SPLASH_EVIEWS_PREFIX_LENGTH} -1 _SPLASH_RELATIVE_PATH)
    set(_SPLASH_OUTPUT "${DMBOOT_EVIEWS_DIR}/${_SPLASH_RELATIVE_PATH}")
else()
    set(_SPLASH_OUTPUT "")
    set(_SPLASH_EXT_PREFIX "${DMBOOT_EXT_MOUNT}/")
    string(LENGTH "${_SPLASH_EXT_PREFIX}" _SPLASH_EXT_PREFIX_LENGTH)
    string(FIND "${DMBOOT_SPLASH_LOGO_PATH}" "${_SPLASH_EXT_PREFIX}" _SPLASH_EXT_AT)
    if(DMBOOT_EXT_DEVICE AND DMBOOT_EXT_MOUNT AND _SPLASH_EXT_AT EQUAL 0)
        string(SUBSTRING "${DMBOOT_SPLASH_LOGO_PATH}" ${_SPLASH_EXT_PREFIX_LENGTH} -1 _SPLASH_EXT_RELATIVE_PATH)
        set(_SPLASH_EXT_OUTPUT "${CMAKE_BINARY_DIR}/ext/${_SPLASH_EXT_RELATIVE_PATH}")
    else()
        set(_SPLASH_EXT_OUTPUT "")
    endif()
endif()

if(DMBOOT_SPLASH_LOGO)
    if(EXISTS "${DMBOOT_SPLASH_ASSETS_DIR}/${DMBOOT_SPLASH_LOGO}.dmvi")
        set(_SPLASH_SOURCE "${DMBOOT_SPLASH_ASSETS_DIR}/${DMBOOT_SPLASH_LOGO}.dmvi")
    else()
        get_filename_component(_SPLASH_SOURCE "${DMBOOT_SPLASH_LOGO}" ABSOLUTE BASE_DIR "${CMAKE_SOURCE_DIR}")
        if(NOT EXISTS "${_SPLASH_SOURCE}")
            file(GLOB _SPLASH_ASSETS RELATIVE "${DMBOOT_SPLASH_ASSETS_DIR}" "${DMBOOT_SPLASH_ASSETS_DIR}/*.dmvi")
            string(REPLACE ".dmvi" "" _SPLASH_ASSETS "${_SPLASH_ASSETS}")
            message(FATAL_ERROR "DMBOOT_SPLASH_LOGO: '${DMBOOT_SPLASH_LOGO}' is neither an asset of ${DMBOOT_SPLASH_ASSETS_DIR} (${_SPLASH_ASSETS}) nor a .dmvi file")
        endif()
    endif()

    if(_SPLASH_OUTPUT)
        add_custom_command(
            OUTPUT "${_SPLASH_OUTPUT}"
            COMMAND ${CMAKE_COMMAND} -E make_directory "${DMBOOT_EVIEWS_DIR}"
            COMMAND python3 "${CMAKE_SOURCE_DIR}/scripts/dmvi_to_dmvir.py" "${_SPLASH_SOURCE}" "${_SPLASH_OUTPUT}"
            DEPENDS "${_SPLASH_SOURCE}" "${CMAKE_SOURCE_DIR}/scripts/dmvi_to_dmvir.py"
            COMMENT "Unpacking splash logo ${_SPLASH_SOURCE} into ${DMBOOT_SPLASH_LOGO_PATH}"
            VERBATIM
        )
        set(DMBOOT_SPLASH_LOGO_FILE "${_SPLASH_OUTPUT}")
        message(STATUS "Splash logo: ${_SPLASH_SOURCE} -> ${DMBOOT_SPLASH_LOGO_PATH}")
    elseif(_SPLASH_EXT_OUTPUT)
        get_filename_component(_SPLASH_EXT_DIR "${_SPLASH_EXT_OUTPUT}" DIRECTORY)
        add_custom_command(
            OUTPUT "${_SPLASH_EXT_OUTPUT}"
            COMMAND ${CMAKE_COMMAND} -E make_directory "${_SPLASH_EXT_DIR}"
            COMMAND python3 "${CMAKE_SOURCE_DIR}/scripts/dmvi_to_dmvir.py" "${_SPLASH_SOURCE}" "${_SPLASH_EXT_OUTPUT}"
            DEPENDS "${_SPLASH_SOURCE}" "${CMAKE_SOURCE_DIR}/scripts/dmvi_to_dmvir.py"
            COMMENT "Unpacking splash logo ${_SPLASH_SOURCE} into build/ext (${DMBOOT_SPLASH_LOGO_PATH})"
            VERBATIM
        )
        add_custom_target(splash_logo_ext ALL DEPENDS "${_SPLASH_EXT_OUTPUT}")
        message(STATUS "Splash logo: ${_SPLASH_SOURCE} -> ${DMBOOT_SPLASH_LOGO_PATH} (external flash)")
    else()
        message(WARNING "DMBOOT_SPLASH_LOGO is set, but DMBOOT_SPLASH_LOGO_PATH (${DMBOOT_SPLASH_LOGO_PATH}) is under neither /eviews/ nor the external flash - the logo is not built")
    endif()
else()
    message(STATUS "No splash logo (DMBOOT_SPLASH_LOGO not set)")
    # A logo of an earlier configuration must not stay in the views image
    if(_SPLASH_OUTPUT AND EXISTS "${_SPLASH_OUTPUT}")
        file(REMOVE "${_SPLASH_OUTPUT}")
    endif()
endif()
