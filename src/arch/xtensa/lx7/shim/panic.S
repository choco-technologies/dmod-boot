/*
 * _xt_panic: where the vectors of the FreeRTOS port go when something fatal happens (an exception with no handler, a double
 * exception). ESP-IDF prints the registers here; this one stops the core, for the debugger (openocd halts at it).
 */
    .section .iram1, "ax"
    .align  4
    .global _xt_panic
    .type   _xt_panic, @function
_xt_panic:
    rsil    a0, 15                      /* all interrupts masked */
1:  j       1b
    .size   _xt_panic, . - _xt_panic
