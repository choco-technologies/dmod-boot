/*******************************************************************************
 * Xtensa LX7 (ESP32-S3) startup code: the entry of the image of a bank
 *
 * ABI:      windowed (the ROM, the FreeRTOS port and the modules are)
 *
 * The selector (selector/) has mapped the bank and switched the instruction cache on, and jumps to the first instruction of
 * the image (DMBOOT_ROM_ORIGIN, the offset 0x200 of the image). Until the vectors of the image are in the RAM, VECBASE is
 * the ROM's: no call (a deep call needs a window overflow, whose handler is in the vectors) before they are.
 *   1. the registers of the windows, the interrupts off, the stack
 *   2. the vectors and the code of the IRAM, the data, from the image through the data bus; the bss zeroed
 *   3. VECBASE to the vectors of the image
 *   4. main(0, NULL)
 *******************************************************************************/

/*------------------------------------------------------------------------------
  The first instruction of the image: the entry. A jump is relative, it needs no literal; the code with its literals follows.
------------------------------------------------------------------------------*/
    .section .vectors, "ax"
    .global Reset_Handler
    .type   Reset_Handler, @function
Reset_Handler:
    j       reset_start
    .size   Reset_Handler, . - Reset_Handler

    .section .startup.text, "ax"
    .align  4
    .literal_position
reset_start:
    movi    a0, 0
    wsr.windowbase a0
    movi    a0, 1
    wsr.windowstart a0
    rsync
    movi    a0, 0
    wsr.intenable a0
    movi    a1, __stack_end__

    /* the vectors and the code of the IRAM: written through the data bus (the instruction bus is fetch only) */
    movi    a2, _iram_start_d
    movi    a3, _iram_end_d
    movi    a4, _iram_load_d
1:  bgeu    a2, a3, 2f
    l32i    a5, a4, 0
    s32i    a5, a2, 0
    addi    a4, a4, 4
    addi    a2, a2, 4
    j       1b
2:
    /* .data */
    movi    a2, __data_start__
    movi    a3, __data_end__
    movi    a4, __data_init_start_d
3:  bgeu    a2, a3, 4f
    l32i    a5, a4, 0
    s32i    a5, a2, 0
    addi    a4, a4, 4
    addi    a2, a2, 4
    j       3b
4:
    /* .bss */
    movi    a2, __bss_start__
    movi    a3, __bss_end__
    movi    a5, 0
5:  bgeu    a2, a3, 6f
    s32i    a5, a2, 0
    addi    a2, a2, 4
    j       5b
6:
    memw
    isync

    /* the vectors of the image from now on; the interrupts stay masked (INTENABLE is 0) until the scheduler enables the tick */
    movi    a2, _vector_table
    wsr.vecbase a2
    movi    a2, 0x40020                     /* PS: WOE (the windows on) | UM (the user vector mode), INTLEVEL 0 */
    wsr.ps  a2
    rsync

    movi    a0, 0
    movi    a6, 0                           /* main( argc = 0, argv = NULL ): a2, a3 of the callee are a6, a7 of the caller */
    movi    a7, 0
    movi    a4, main
    callx4  a4
7:  j       7b                              /* main returned (it should not) */

/*******************************************************************************
 * END OF FILE
 *******************************************************************************/
