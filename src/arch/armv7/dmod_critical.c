/**
 * MIT License
 * 
 * Copyright (c) 2024 Patryk Kubiak
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * 
 * @brief Critical section implementation for ARMv7-M architecture
 * @date 2024-11-06
 * @author Patryk Kubiak <patryk.kubiak90@gmail.com>
 * 
 * This file implements critical section functions for ARMv7-M (Cortex-M3/M4/M7)
 * processors by manipulating the PRIMASK register to disable/enable interrupts.
 * 
 * The implementation supports nested critical sections by tracking the nesting
 * level. Interrupts are only re-enabled when exiting the outermost critical
 * section (nesting level = 0).
 * 
 * Note: The nesting counter is safe to modify because interrupts are always
 * disabled when entering/exiting critical sections. In EnterCritical, we
 * disable interrupts first, then increment. In ExitCritical, interrupts are
 * still disabled from the previous EnterCritical call, so the decrement is safe.
 */
#include "dmod.h"
#include <stdint.h>
#include <stddef.h>

static uint32_t critical_nesting = 0;

/**
 * @brief Assertion handler for critical section functions
 * 
 * This function is called when an assertion fails in the critical section code.
 * It logs the error message and halts the system to prevent further damage.
 * 
 * @param Condition The condition that failed (should be false)
 * @param Message A message describing the assertion failure
 * @param File The source file where the assertion failed
 * @param Line The line number in the source file where the assertion failed
 * @param Function The function name where the assertion failed
 */
void Dmod_Assert( int Condition, const char* Message, const char* File, int Line, const char* Function )
{
    if( !Condition )
    {
        DMOD_LOG_ERROR("Assertion failed: %s, at %s:%d in function %s\n", Message, File, Line, Function);
        __asm volatile ("BKPT #0"); // Trigger a breakpoint for debugging
        while(1); // Halt the system
    }
}

/**
 * @brief Enter critical section
 * 
 * This function disables interrupts by setting the PRIMASK register.
 * It supports nested critical sections by tracking the nesting level.
 * 
 * The sequence is:
 * 1. Disable interrupts (atomic operation)
 * 2. Increment nesting counter (safe because interrupts are now disabled)
 */
void Dmod_EnterCritical(void)
{
    __asm volatile (
        "CPSID i    \n"  /* Disable interrupts */
        ::: "memory"
    );
    critical_nesting++;
}

/**
 * @brief Exit critical section
 * 
 * This function re-enables interrupts by clearing the PRIMASK register,
 * but only when exiting the outermost critical section (nesting level = 0).
 * 
 * The sequence is:
 * 1. Decrement nesting counter (safe because interrupts are still disabled)
 * 2. If counter reaches 0, enable interrupts (atomic operation)
 */
void Dmod_ExitCritical(void)
{
    DMOD_ASSERT(critical_nesting > 0);
    
    if (critical_nesting > 0)
    {
        critical_nesting--;
        if (critical_nesting == 0)
        {
            __asm volatile (
                "CPSIE i    \n"  /* Enable interrupts */
                ::: "memory"
            );
        }
    }
}

/**
 * @brief Get the remaining stack size
 * 
 * This function returns the number of bytes still available on the current
 * stack. It reads the Main Stack Pointer (MSP) register and computes the
 * distance to the bottom of the stack region defined by the linker symbol
 * __stack_start__.
 * 
 * On ARMv7-M the stack is full-descending: the SP starts at the top
 * (__stack_end__) and moves toward the bottom (__stack_start__) as frames
 * are pushed. The remaining (free) space is therefore:
 *
 *   remaining = MSP - __stack_start__
 * 
 * @return Remaining stack size in bytes, or 0 if the stack has overflowed
 */
size_t Dmod_GetLeftStackSize(void)
{
    extern uint32_t __stack_start__;

    uint32_t sp;
    __asm volatile (
        "MRS %0, MSP\n"
        : "=r"(sp)
    );

    uint32_t stackBase = (uint32_t)&__stack_start__;
    if (sp <= stackBase)
    {
        return 0;
    }

    return (size_t)(sp - stackBase);
}
