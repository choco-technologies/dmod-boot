/**
 * @brief Pre-RTOS guard for Dmod_Mutex_New (ARMv7-M)
 *
 * The dmosi bridge library provides a strong Dmod_Mutex_New that calls
 * dmosi_mutex_create(), which in turn calls pvPortMalloc() +
 * xSemaphoreCreateRecursiveMutex().  Both succeed before vTaskStartScheduler()
 * because FreeRTOS heap allocation does not require the scheduler.  However,
 * dmosi_mutex_lock() returns -ENOTSUP when !dmosi_is_started(), so any caller
 * that obtains a non-NULL mutex handle before the scheduler starts and then
 * tries to lock it will fail.
 *
 * This wrapper (enabled via -Wl,--wrap=Dmod_Mutex_New) returns NULL when the
 * scheduler has not yet been started.  NULL causes callers such as dmvfs to
 * fall back to Dmod_EnterCritical / Dmod_ExitCritical (interrupt-disable
 * critical sections), which work correctly both before and after RTOS start.
 *
 * After vTaskStartScheduler() the wrapper forwards to the real implementation
 * so proper recursive RTOS mutexes are created as usual.
 */

#include <stdbool.h>

/* Resolved at link time from dmosi_freertos */
extern bool dmosi_is_started(void);

/* The real (unwrapped) symbol comes from the dmosi bridge library */
extern void* __real_Dmod_Mutex_New(bool Recursive);

void* __wrap_Dmod_Mutex_New(bool Recursive)
{
    if (!dmosi_is_started())
    {
        return NULL;
    }
    return __real_Dmod_Mutex_New(Recursive);
}
