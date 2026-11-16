#include <xtensa/coreasm.h>
#include <xtensa/config/core.h>

/*
 * dmboot_fault_trampoline: where a thread continues after a fault of it was contained (see fault.c)
 *
 * The exception returns here with the thread's stack rewound to its top (a1), the argument of the entry in a2 and the entry
 * in a3, in the register window the faulting code was running in. That code is gone, but its callers are still in the
 * windows of the core: WINDOWSTART marks them as live, and the first call that needs a window of them would spill them to
 * where their frames were - over the frames of the entry, which are in the same place now. They are forgotten here: the
 * only live window is this one. Then the entry is called the way any function is (it does not return).
 *
 * In the IRAM, like the vectors: it runs on the way out of an exception.
 */
    .section .iram1, "ax"
    .align  4
    .global dmboot_fault_trampoline
    .type   dmboot_fault_trampoline, @function
dmboot_fault_trampoline:
    rsr.windowbase  a4
    movi    a5, 1
    ssl     a4                          /* SAR = 32 - WINDOWBASE: a shift left by WINDOWBASE */
    sll     a5, a5
    wsr.windowstart a5                  /* only the window of this code is live */
    rsync
    mov     a6, a2                      /* the argument of the callee (a6 of the caller is a2 of a call4's callee) */
    callx4  a3
1:  j       1b                          /* the entry does not return */
    .size   dmboot_fault_trampoline, . - dmboot_fault_trampoline

/*
 * xt_debugexception: the debug exception of the core - the stack guard of the thread that runs was written to (see fault.c)
 *
 * The port of FreeRTOS has it as a weak symbol that panics; this one panics the same way for everything but a data
 * breakpoint. The core is at the debug level here (above every interrupt), and the stack in a1 is the one that overflowed:
 * nothing can run on it. What is needed is saved, and the exception returns to dmboot_guard_trampoline on a stack of
 * its own, with the interrupts masked up to the level of the kernel - the state of the abandoned code is not returned
 * to: the thread is rewound to the top of its stack (or, when it cannot be contained, the system halts), which is
 * why a1 and the registers are not kept. a0 is the only register free (the vector put it in EXCSAVE6).
 */
    .section .iram1, "ax"
    .align  4
    .global xt_debugexception
    .type   xt_debugexception, @function
xt_debugexception:
    rsr.debugcause  a0
    bbci    a0, 2, 1f                   /* DEBUGCAUSE.DBREAK: no, something else: the panic of the port */
    movi    a0, dmboot_guard_hit
    s32i    a1, a0, 4                   /* sp */
    rsr.epc6        a1
    s32i    a1, a0, 0                   /* pc */
    rsr.eps6        a1
    s32i    a1, a0, 8                   /* ps */
    movi    a0, dmboot_guard_trampoline
    wsr.epc6        a0
    srli    a1, a1, 5                   /* PS without INTLEVEL and EXCM (the abandoned code is not returned to) ... */
    slli    a1, a1, 5
    addi    a1, a1, XCHAL_EXCM_LEVEL    /* ... masked up to the kernel's level until the thread is resumed */
    wsr.eps6        a1
    movi    a1, dmboot_guard_stack_top
    l32i    a1, a1, 0
    rsync
    rfi     6

1:  movi    a0, 1                       /* PANIC_RSN_DEBUGEXCEPTION, as the default does */
    wsr.exccause    a0
    rsr.epc6        a0
    wsr.epc1        a0
    rsr.excsave6    a0
    wsr.excsave1    a0
    call0   _xt_panic
    .size   xt_debugexception, . - xt_debugexception

/*
 * dmboot_guard_trampoline: the C part of the handling of the overflow, then the thread is resumed in the entry
 *
 * The windows of the abandoned code are forgotten (see dmboot_fault_trampoline). dmboot_xtensa_guard_fault() decides, and
 * either halts the system or fills in dmboot_guard_recovery, from where the thread is resumed the way it is in
 * dmboot_fault_trampoline, with the interrupts unmasked.
 */
    .align  4
    .type   dmboot_guard_trampoline, @function
dmboot_guard_trampoline:
    rsr.windowbase  a4
    movi    a5, 1
    ssl     a4
    sll     a5, a5
    wsr.windowstart a5
    rsync
    call4   dmboot_xtensa_guard_fault
    rsr.windowbase  a4
    movi    a5, 1
    ssl     a4
    sll     a5, a5
    wsr.windowstart a5
    rsync
    movi    a4, dmboot_guard_recovery
    l32i    a1, a4, 0                   /* stack_top */
    l32i    a2, a4, 4                   /* arg */
    l32i    a3, a4, 8                   /* entry */
    mov     a6, a2
    rsil    a4, 0                       /* the thread runs with the interrupts enabled again */
    callx4  a3
2:  j       2b
    .size   dmboot_guard_trampoline, . - dmboot_guard_trampoline
