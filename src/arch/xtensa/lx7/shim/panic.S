/*
 * _xt_panic: where the vectors of the FreeRTOS port go when something fatal happens (an exception with no handler, a double
 * exception, an interrupt nobody handles). It must not use a stack (after a double exception the stack may be the very trouble):
 * it keeps what is known in the RTC slow memory (which a reset of the system does not clear: dmboot_report_last_crash() prints it at the
 * next start) and resets the system - a device that stops with nothing on the screen is no use to anybody. A debugger that wants the
 * core to stay can halt it at the vector before the reset (the reset follows at once: break at _xt_panic).
 *
 * The record at 0x50001F40: [0] the mark, [1..16] dmboot_last_exception, [17..21] EXCCAUSE, EXCVADDR, EPC1, EPC2, DEPC.
 */
#define RECORD          0x50001F40
#define RECORD_MARK     0xC4A5E0D1
#define RTC_OPTIONS0    0x60008000          /* RTC_CNTL_OPTIONS0_REG: bit 31 is SW_SYS_RST */

    .section .iram1, "ax"
    .literal_position
    .literal .Lrecord, RECORD
    .literal .Lmark, RECORD_MARK
    .literal .Lsource, dmboot_last_exception
    .literal .Loptions, RTC_OPTIONS0
    .literal .Lreset, 0x80000000
    .align  4
    .global _xt_panic
    .type   _xt_panic, @function
_xt_panic:
    rsil    a0, 15                      /* all interrupts masked */
    l32r    a2, .Lrecord
    l32r    a3, .Lmark
    s32i    a3, a2, 0
    addi    a2, a2, 4
    l32r    a4, .Lsource
    movi    a5, 16
1:  l32i    a6, a4, 0
    s32i    a6, a2, 0
    addi    a4, a4, 4
    addi    a2, a2, 4
    addi    a5, a5, -1
    bnez    a5, 1b
    rsr.exccause a6
    s32i    a6, a2, 0
    rsr.excvaddr a6
    s32i    a6, a2, 4
    rsr.epc1 a6
    s32i    a6, a2, 8
    rsr.epc2 a6
    s32i    a6, a2, 12
    rsr.depc a6
    s32i    a6, a2, 16
    memw
    l32r    a2, .Loptions
    l32i    a3, a2, 0
    l32r    a4, .Lreset
    or      a3, a3, a4
    s32i    a3, a2, 0                   /* the system resets */
2:  j       2b
    .size   _xt_panic, . - _xt_panic
