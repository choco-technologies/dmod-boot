/**
 * @file dmod_sal_printf.c
 * @brief DMOD Printf and Mutex implementation for dmod-boot
 * 
 * This file implements only the Printf and Mutex DMOD SAL functions.
 * Memory allocation is provided by dmheap library.
 */

#include "dmod.h"
#include "dmod_sal.h"
#include "dmod_printf.h"
#include <stdarg.h>

/**
 * @brief Printf implementation (recommended by DMOD)
 * This uses the existing dmod_printf implementation
 */
DMOD_INPUT_API_DECLARATION(Dmod, 1.0, int, _Printf, (const char* Format, ...))
{
    va_list args;
    va_start(args, Format);
    int result = Dmod_Vprintf(Format, args);
    va_end(args);
    return result;
}

/* Mutex functions - not implemented for bare-metal (single-threaded) */
DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void*, _Mutex_New, (void))
{
    return (void*)1;  /* Return non-NULL to indicate success */
}

DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void, _Mutex_Delete, (void* Mutex))
{
    (void)Mutex;  /* Unused */
}

DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void, _Mutex_Lock, (void* Mutex))
{
    (void)Mutex;  /* Unused - single threaded */
}

DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void, _Mutex_Unlock, (void* Mutex))
{
    (void)Mutex;  /* Unused - single threaded */
}
