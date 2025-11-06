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
 */
#include "dmod.h"
#include <stdint.h>

static volatile uint32_t critical_nesting = 0;

/**
 * @brief Enter critical section
 * 
 * This function disables interrupts by setting the PRIMASK register.
 * It supports nested critical sections by tracking the nesting level.
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
 */
void Dmod_ExitCritical(void)
{
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
