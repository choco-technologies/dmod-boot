# GDB initialization script for connecting to Renode
# This script automatically connects to Renode and sets up debugging environment
# Generated for target: STM32F746xG

# Connect to Renode GDB server running on localhost:3333
target extended-remote localhost:3333

# Renode loads the firmware automatically, so we don't need to load it via GDB
# The firmware is already loaded by the Renode platform script

# Continue execution
continue
