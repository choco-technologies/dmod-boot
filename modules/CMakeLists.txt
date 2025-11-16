# =====================================================================
#               DMOD Modules Build Configuration
# =====================================================================
cmake_minimum_required(VERSION 3.18)

# This directory builds DMOD modules with -DDMOD_MODE=DMOD_MODULE
# The modules are then packaged into modules.dmp using todmp tool

# ======================================================================
#               Configuration
# ======================================================================
# Ensure DMOD_MODE is set to MODULE mode for all modules built here
set(DMOD_MODE "DMOD_MODULE" CACHE STRING "DMOD build mode" FORCE)

# ======================================================================
#               Add Module Subdirectories
# ======================================================================
add_subdirectory(dmffs)
