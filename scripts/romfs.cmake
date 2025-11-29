# This script sets up a ROM filesystem using dmffs and integrates it into the build
# It checks for the required tools, creates the ROMFS image, and embeds it into the firmware

# Check if DMBOOT_ROMFS_DIR is set and exists
if(DMBOOT_ROMFS_DIR AND EXISTS "${DMBOOT_ROMFS_DIR}")
    message(STATUS "ROMFS directory specified: ${DMBOOT_ROMFS_DIR}")    
    # Locate make_dmffs executable if not provided
    if(NOT DMBOOT_MAKE_DMFFS_MODULE)
        # Search the make_dmffs.dmf 