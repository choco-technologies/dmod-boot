#include <string.h>
#include "dmod.h"
#include "dmlog.h"
#include "dmheap.h"

extern void* __logs_start__;
extern void* __logs_end__;
extern void* __dmod_inputs_start;
extern void* __dmod_inputs_end;
extern void* __heap_start__;
extern void* __heap_end__;

void delay(int cycles)
{
    for(volatile int i = 0; i < cycles; i++);
}

void HardFault_Handler(void)
{
    dmlog_ctx_t ctx = dmlog_get_default();
    dmlog_puts(ctx, "HardFault detected!\n");
    while(1);
}

int main(int argc, char** argv) 
{
    void* logs_start = &__logs_start__;
    void* logs_end = &__logs_end__;
    dmlog_index_t  logs_size = (dmlog_index_t)((uintptr_t)logs_end - (uintptr_t)logs_start);
    
    memset(logs_start, 0, logs_size);

    dmlog_ctx_t ctx = dmlog_create(logs_start, logs_size);
    dmlog_set_as_default(ctx);

    dmlog_puts(ctx, "DMOD-Boot started\n");

    void* heap_start = &__heap_start__;
    void* heap_end = &__heap_end__;
    size_t heap_size = (size_t)((uintptr_t)heap_end - (uintptr_t)heap_start);

    if(!dmheap_init(heap_start, heap_size, sizeof(void*)))
    {
        DMOD_LOG_ERROR("Heap initialization failed!\n");
        while(1);
    }
    DMOD_LOG_INFO("Heap initialized: Start=0x%X, Size=%u bytes\n", (uintptr_t)heap_start, (unsigned int)heap_size);

    void* inputs_start = &__dmod_inputs_start;
    void* inputs_end = &__dmod_inputs_end;
    size_t inputs_size = (size_t)((uintptr_t)inputs_end - (uintptr_t)inputs_start);

    DMOD_LOG_INFO("Inputs start address: 0x%X\n", (uintptr_t)inputs_start);
    DMOD_LOG_INFO("Inputs size: %u bytes\n", (unsigned int)inputs_size);

    Dmod_Initialize();

    int i = 0;
    while(1)
    {
        DMOD_LOG_INFO("Waiting for better times... ID: %d\n", i++);
        delay(1000000);
    }
    return 0;
}