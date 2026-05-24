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
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *
 * @brief Critical section implementation for Xtensa ESP32-S3 architecture
 * @date  2024-11-06
 * @author Patryk Kubiak <patryk.kubiak90@gmail.com>
 *
 * Implements nested critical sections by saving/restoring the PS (Processor
 * State) register's interrupt level.  On entry the interrupt level is raised
 * to 15 (all interrupts masked); on exit the original PS is restored when the
 * outermost critical section is left.
 *
 * Using the Xtensa RSIL (Read and Set Interrupt Level) instruction ensures
 * that the read-modify-write is atomic.
 */

#include "dmod.h"
#include <stdint.h>

static uint32_t critical_nesting = 0;
static uint32_t saved_ps         = 0;

/**
 * @brief Assertion handler for critical section functions
 */
void Dmod_Assert( int Condition, const char* Message, const char* File,
                  int Line, const char* Function )
{
    if( !Condition )
    {
        DMOD_LOG_ERROR( "Assertion failed: %s, at %s:%d in function %s\n",
                        Message, File, Line, Function );
        __asm__ volatile ( "break 1, 15" );  /* Xtensa debug breakpoint */
        while( 1 );
    }
}

/**
 * @brief Enter critical section
 *
 * Raises PS.INTLEVEL to 15, masking all interrupts.  Saves the original PS
 * only for the outermost nesting level so that it can be restored on exit.
 */
void Dmod_EnterCritical( void )
{
    uint32_t ps;
    __asm__ volatile (
        "rsil %0, 15\n"   /* read PS into ps, then set INTLEVEL = 15 */
        : "=a"( ps )
        :
        : "memory"
    );
    if( critical_nesting == 0 )
    {
        saved_ps = ps;
    }
    critical_nesting++;
}

/**
 * @brief Exit critical section
 *
 * Decrements the nesting counter.  When the counter reaches zero the original
 * PS is written back, re-enabling interrupts at the level they had before the
 * outermost Dmod_EnterCritical() call.
 */
void Dmod_ExitCritical( void )
{
    DMOD_ASSERT( critical_nesting > 0 );

    if( critical_nesting > 0 )
    {
        critical_nesting--;
        if( critical_nesting == 0 )
        {
            __asm__ volatile (
                "wsr    %0, PS\n"
                "rsync\n"
                :
                : "a"( saved_ps )
                : "memory"
            );
        }
    }
}
