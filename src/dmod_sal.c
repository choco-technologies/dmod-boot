/**
 * @file dmod_sal.c
 * @brief DMOD System Abstraction Layer implementation for dmod-boot
 * 
 * This file implements the required DMOD SAL functions for embedded systems.
 * Memory allocation is provided by dmheap, logging by dmod_printf.
 */

#include "dmod.h"
#include "dmod_sal.h"
#include "dmheap.h"
#include "dmod_printf.h"
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>

/* Heap buffer for dmheap */
#ifndef DMHEAP_SIZE
#define DMHEAP_SIZE 32768  /* 32KB default */
#endif

static char g_heap_buffer[DMHEAP_SIZE] __attribute__((aligned(8)));
static bool g_heap_initialized = false;

/**
 * @brief Initialize the heap
 */
static void ensure_heap_initialized(void) {
    if (!g_heap_initialized) {
        if (dmheap_init(g_heap_buffer, DMHEAP_SIZE, 8)) {
            g_heap_initialized = true;
            Dmod_Printf("[DMOD] Heap initialized: %d bytes\n", DMHEAP_SIZE);
        } else {
            Dmod_Printf("[DMOD] ERROR: Failed to initialize heap\n");
        }
    }
}

/**
 * @brief Allocate memory (required by DMOD)
 */
DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void*, _MallocEx, (size_t Size, const char* ModuleName))
{
    ensure_heap_initialized();
    return dmheap_malloc(Size, ModuleName);
}

/**
 * @brief Free memory (required by DMOD)
 */
DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void, _FreeEx, (void* Ptr, const char* ModuleName))
{
    (void)ModuleName;  /* Unused parameter */
    dmheap_free(Ptr, false);
}

/**
 * @brief Allocate aligned memory (required by DMOD)
 */
DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void*, _AlignedMallocEx, (size_t Alignment, size_t Size, const char* ModuleName))
{
    ensure_heap_initialized();
    return dmheap_aligned_alloc(Alignment, Size, ModuleName);
}

/**
 * @brief Reallocate memory (required by DMOD)
 */
DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void*, _ReallocEx, (void* Ptr, size_t Size, const char* ModuleName))
{
    ensure_heap_initialized();
    return dmheap_realloc(Ptr, Size, ModuleName);
}

/**
 * @brief Free all memory allocated by a module (required by DMOD)
 */
DMOD_INPUT_API_DECLARATION(Dmod, 1.0, void, _FreeModule, (const char* ModuleName))
{
    dmheap_unregister_module(ModuleName);
}

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
