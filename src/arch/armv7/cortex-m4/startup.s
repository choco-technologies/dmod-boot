/*******************************************************************************
* author: Daniel Zorychta, danz@jabster.pl
*
* File is based on Freddie Chopin's startup file
*
* chip: ARMv7-M (Cortex-M4)
* compiler: arm-none-eabi-gcc
*
* description:
* ARMv7-M (Cortex-M4) assembly startup code
*******************************************************************************/

/* CONTROL - The special-purpose control register */
#define CONTROL_THREAD_UNPRIVILEGED_bit     0
#define CONTROL_ALTERNATE_STACK_bit         1

#define CONTROL_THREAD_UNPRIVILEGED         (1 << CONTROL_THREAD_UNPRIVILEGED_bit)
#define CONTROL_ALTERNATE_STACK             (1 << CONTROL_ALTERNATE_STACK_bit)

/*==============================================================================
Vector table for ARM Cortex-M4
==============================================================================*/

.section .vectors, "a", %progbits
.balign 2
.global vectors

vectors:
    .word   __stack_end__                    /* 0: Initial Stack Pointer */
    .word   Reset_Handler                    /* 1: Reset Handler */
    .word   NMI_Handler                      /* 2: NMI Handler */
    .word   HardFault_Handler                /* 3: Hard Fault Handler */
    .word   MemManage_Handler                /* 4: MPU Fault Handler */
    .word   BusFault_Handler                 /* 5: Bus Fault Handler */
    .word   UsageFault_Handler               /* 6: Usage Fault Handler */
    .word   0                                /* 7: Reserved */
    .word   0                                /* 8: Reserved */
    .word   0                                /* 9: Reserved */
    .word   0                                /* 10: Reserved */
    .word   SVC_Handler                      /* 11: SVCall Handler */
    .word   DebugMon_Handler                 /* 12: Debug Monitor Handler */
    .word   0                                /* 13: Reserved */
    .word   PendSV_Handler                   /* 14: PendSV Handler */
    .word   SysTick_Handler                  /* 15: SysTick Handler */

/*==============================================================================
ARMv7-M (Cortex-M4) startup code
==============================================================================*/

.text
.balign 2
.syntax unified
.thumb
.thumb_func
.global Reset_Handler

Reset_Handler:
/*==============================================================================
Initialize the process stack pointer
==============================================================================*/
   ldr      r0, =__stack_end__
   msr      PSP, r0

/*==============================================================================
Thread mode uses process stack (PSP) and is privileged
==============================================================================*/
   movs     r0, #2                          // CONTROL_ALTERNATE_STACK = (1 << 1) = 2
   msr      CONTROL, r0
   isb

/*==============================================================================
Branch to low_level_init_0() function (.data and .bss are not initialized!)
==============================================================================*/
   ldr      r0, =low_level_init_0
   blx      r0

/*==============================================================================
Initialize .data section
==============================================================================*/
   ldr      r1, =__data_init_start__
   ldr      r2, =__data_start__
   ldr      r3, =__data_end__

1: cmp      r2, r3
   ittt     lo
   ldrlo    r0, [r1], #4
   strlo    r0, [r2], #4
   blo      1b

/*==============================================================================
Zero-init .bss section
==============================================================================*/
   movs     r0, #0
   ldr      r1, =__bss_start__
   ldr      r2, =__bss_end__

1: cmp      r1, r2
   itt      lo
   strlo    r0, [r1], #4
   blo      1b

/*==============================================================================
Call C++ constructors for global and static objects
==============================================================================*/
#ifdef __USES_CXX
   ldr      r0, =__libc_init_array
   blx      r0
#endif

/*==============================================================================
Branch to low_level_init_1() function
==============================================================================*/
   ldr      r0, =low_level_init_1
   blx      r0

/*==============================================================================
Branch to main() with link
==============================================================================*/
   movs     r0, #0                          // argc = 0 (no command line arguments)
   movs     r1, #0                          // argv = NULL (no argument array)
   ldr      r2, =main
   blx      r2

/*==============================================================================
Call C++ destructors for global and static objects
==============================================================================*/
#ifdef __USES_CXX
   ldr      r0, =__libc_fini_array
   blx      r0
#endif

/*==============================================================================
On return - loop till the end of the world
==============================================================================*/
   b      .

/*==============================================================================
__default_low_level_init() - replacement for undefined low_level_init_0()
and/or low_level_init_1(). This function just returns.
==============================================================================*/

.text
.balign 2
.syntax unified
.thumb
.thumb_func
.global __default_low_level_init

__default_low_level_init:
   bx      lr

/*==============================================================================
Default exception handlers - infinite loop for unhandled exceptions
==============================================================================*/

.text
.balign 2
.syntax unified
.thumb
.thumb_func
.global __default_handler

__default_handler:
   b      __default_handler

/*==============================================================================
assign undefined low_level_init_0() and/or low_level_init_1() to
__default_low_level_init()
==============================================================================*/

.weak   low_level_init_0
.global low_level_init_0
.set    low_level_init_0, __default_low_level_init

.weak   low_level_init_1
.global low_level_init_1
.set    low_level_init_1, __default_low_level_init

/*==============================================================================
assign undefined exception handlers to __default_handler
==============================================================================*/

.weak   NMI_Handler
.global NMI_Handler
.set    NMI_Handler, __default_handler

.weak   HardFault_Handler
.global HardFault_Handler
.set    HardFault_Handler, __default_handler

.weak   MemManage_Handler
.global MemManage_Handler
.set    MemManage_Handler, __default_handler

.weak   BusFault_Handler
.global BusFault_Handler
.set    BusFault_Handler, __default_handler

.weak   UsageFault_Handler
.global UsageFault_Handler
.set    UsageFault_Handler, __default_handler

.weak   SVC_Handler
.global SVC_Handler
.set    SVC_Handler, __default_handler

.weak   DebugMon_Handler
.global DebugMon_Handler
.set    DebugMon_Handler, __default_handler

.weak   PendSV_Handler
.global PendSV_Handler
.set    PendSV_Handler, __default_handler

.weak   SysTick_Handler
.global SysTick_Handler
.set    SysTick_Handler, __default_handler

/*******************************************************************************
END OF FILE
*******************************************************************************/
