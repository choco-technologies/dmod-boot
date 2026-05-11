/*******************************************************************************
 * Xtensa LX7 (ESP32-S3) startup code
 *
 * chip:     Xtensa LX7 (ESP32-S3)
 * ABI:      call0 (no register-window overhead; compiled with -mabi=call0)
 * compiler: xtensa-esp32s3-elf-gcc
 *
 * Startup sequence mirrors the ARMv7-M startup so that the rest of the
 * project's C runtime initialisation conventions are preserved:
 *   1. Disable all interrupts (PS.INTLEVEL = 15)
 *   2. Set up the stack pointer
 *   3. Call low_level_init_0()  (.data / .bss NOT yet initialised)
 *   4. Copy .data from ROM image to RAM
 *   5. Zero-initialise .bss
 *   6. Call low_level_init_1()
 *   7. Call main(0, NULL)
 *   8. Loop forever on return
 *******************************************************************************/

/*==============================================================================
  Reset vector – placed in the .vectors section so the linker script can
  position it at the start of the ROM (IRAM) region.
==============================================================================*/

.section .vectors, "ax"
.balign 4
.global Reset_Handler
.type   Reset_Handler, @function

Reset_Handler:

/*------------------------------------------------------------------------------
  Disable all interrupts by setting PS.INTLEVEL to 15 (maximum level).
  Using RSIL to read the old PS value (discarded) and set the new level.
------------------------------------------------------------------------------*/
    rsil    a0, 15                  /* PS.INTLEVEL = 15 – all interrupts masked */
    rsync

/*------------------------------------------------------------------------------
  Set up the process stack pointer.
  __stack_end__ is defined by the linker script (top of the .stack section).
------------------------------------------------------------------------------*/
    movi    a1, __stack_end__

/*------------------------------------------------------------------------------
  Call low_level_init_0() – hardware clock / watchdog setup that must happen
  before .data / .bss are initialised.  Uses call0 ABI: return address in a0,
  callee must preserve a1 (sp).
------------------------------------------------------------------------------*/
    call0   low_level_init_0

/*------------------------------------------------------------------------------
  Copy initialised data (.data section) from its load address in ROM to its
  run-time address in RAM.

  Registers used (caller-saved in call0 ABI, safe to clobber here):
    a0 – source pointer  (__data_init_start__)
    a2 – destination pointer (__data_start__)
    a3 – end of destination  (__data_end__)
    a4 – temporary word value
------------------------------------------------------------------------------*/
    movi    a0, __data_init_start__
    movi    a2, __data_start__
    movi    a3, __data_end__
    bgeu    a2, a3, .Ldata_done     /* skip if .data is empty */
.Ldata_loop:
    l32i    a4, a0, 0
    s32i    a4, a2, 0
    addi    a0, a0, 4
    addi    a2, a2, 4
    bltu    a2, a3, .Ldata_loop
.Ldata_done:

/*------------------------------------------------------------------------------
  Zero-initialise .bss section.

  Registers used:
    a0 – zero constant
    a2 – current pointer (__bss_start__)
    a3 – end pointer     (__bss_end__)
------------------------------------------------------------------------------*/
    movi    a0, 0
    movi    a2, __bss_start__
    movi    a3, __bss_end__
    bgeu    a2, a3, .Lbss_done      /* skip if .bss is empty */
.Lbss_loop:
    s32i    a0, a2, 0
    addi    a2, a2, 4
    bltu    a2, a3, .Lbss_loop
.Lbss_done:

/*------------------------------------------------------------------------------
  Re-load the stack pointer (may have been modified during init).
------------------------------------------------------------------------------*/
    movi    a1, __stack_end__

/*------------------------------------------------------------------------------
  Call low_level_init_1() – second-stage initialisation with .data / .bss
  already set up (e.g. peripheral and RTOS clock initialisation).
------------------------------------------------------------------------------*/
    call0   low_level_init_1

/*------------------------------------------------------------------------------
  Call main(argc=0, argv=NULL).
  In the call0 ABI the first two arguments are passed in a2 and a3.
------------------------------------------------------------------------------*/
    movi    a2, 0                   /* argc = 0  */
    movi    a3, 0                   /* argv = NULL */
    call0   main

/*------------------------------------------------------------------------------
  Loop forever if main() returns (should never happen in a bootloader).
------------------------------------------------------------------------------*/
.Lforever:
    j       .Lforever

/*==============================================================================
  Default (weak) implementations of low_level_init_0 / low_level_init_1.
  A board-specific file may override them by providing a strong symbol.
==============================================================================*/

.balign 4
.global __default_low_level_init
.type   __default_low_level_init, @function
__default_low_level_init:
    ret.n

.weak   low_level_init_0
.global low_level_init_0
.set    low_level_init_0, __default_low_level_init

.weak   low_level_init_1
.global low_level_init_1
.set    low_level_init_1, __default_low_level_init

/*******************************************************************************
 * END OF FILE
 *******************************************************************************/
