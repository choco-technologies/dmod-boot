/*
 * main.c - Application for dmod-boot
 * 
 * Demonstrating DMOD and dmheap integration with ring buffer debug output
 */

#include "dmod_printf.h"
#include "dmod.h"
#include "dmheap.h"
#include <stdint.h>
#include <string.h>

/* Heap buffer for dmheap */
#ifndef DMHEAP_SIZE
#define DMHEAP_SIZE 32768  /* 32KB default */
#endif

static char g_heap_buffer[DMHEAP_SIZE] __attribute__((aligned(8)));

/* Simple delay function */
static void delay(volatile uint32_t count)
{
    while (count--);
}

int main(void)
{
    uint32_t counter = 0;
    
    /* Initialize log ring buffer */
    Dmod_Log_Init();
    
    /* Print startup message */
    Dmod_Printf("=== dmod-boot with DMOD & dmheap ===\n");
    Dmod_Printf("System starting...\n");
    Dmod_Printf("Ring buffer debug output enabled\n\n");
    
    /* Initialize dmheap */
    if (dmheap_init(g_heap_buffer, DMHEAP_SIZE, 8)) {
        Dmod_Printf("Heap initialized: %d bytes\n", DMHEAP_SIZE);
    } else {
        Dmod_Printf("ERROR: Failed to initialize heap\n");
        while (1);  /* Halt on error */
    }
    
    /* Demonstrate DMOD Printf */
    Dmod_Printf("Testing DMOD Printf API...\n");
    
    /* Demonstrate memory allocation with dmheap */
    Dmod_Printf("\n--- Testing dmheap memory allocation ---\n");
    
    /* Test basic allocation */
    void* ptr1 = Dmod_MallocEx(256, "main");
    if (ptr1) {
        Dmod_Printf("Allocated 256 bytes at %p\n", ptr1);
        memset(ptr1, 0xAA, 256);
        Dmod_Printf("Memory filled with 0xAA\n");
        Dmod_FreeEx(ptr1, "main");
        Dmod_Printf("Memory freed\n");
    }
    
    /* Test aligned allocation */
    void* ptr2 = Dmod_AlignedMallocEx(64, 512, "main");
    if (ptr2) {
        Dmod_Printf("Allocated 512 bytes aligned to 64 at %p\n", ptr2);
        Dmod_FreeEx(ptr2, "main");
        Dmod_Printf("Aligned memory freed\n");
    }
    
    Dmod_Printf("\n--- Entering main loop ---\n\n");
    
    /* Main loop */
    while (1) {
        Dmod_Printf("Counter: %u (0x%X)\n", counter, counter);
        counter++;
        
        /* Allocate and free memory in loop to demonstrate dynamic allocation */
        if (counter % 10 == 0) {
            void* temp = Dmod_MallocEx(128, "main");
            if (temp) {
                Dmod_Printf("  [Temp allocation: %p]\n", temp);
                Dmod_FreeEx(temp, "main");
            }
        }
        
        /* Delay between prints */
        delay(1000000);
    }
    
    return 0;
}
