/* The selector (selector/): ARMv7-M - the reset handler is the entry, the stack grows down from the top of its place at the
   bottom of the RAM (DMSEL_STACK_SIZE: selector/linker/common.ld) */
ENTRY(Reset_Handler)
_estack = ORIGIN(RAM) + DMSEL_STACK_SIZE;
