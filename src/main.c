#include <string.h>
#include <stdbool.h>
#include "dmod.h"
#include "dmlog.h"
#include "dmheap.h"
#include "dmvfs.h"

extern void* __logs_start__;
extern void* __logs_end__;
extern void* __dmod_inputs_start;
extern void* __dmod_inputs_end;
extern void* __heap_start__;
extern void* __heap_end__;

// Embedded file symbols (weak, so they default to NULL if not provided)
extern char __startup_dmp_start__ __attribute__((weak));
extern char __startup_dmp_end__ __attribute__((weak));
extern char __user_data_start__ __attribute__((weak));
extern char __user_data_end__ __attribute__((weak));

// Environment variable storage for embedded system
#define MAX_ENV_VARS 10
#define ENV_NAME_SIZE 32
#define ENV_VALUE_SIZE 64

typedef struct {
    char name[ENV_NAME_SIZE];
    char value[ENV_VALUE_SIZE];
} EnvVar;

static EnvVar g_envVars[MAX_ENV_VARS];
static int g_envVarCount = 0;

// Helper function to copy string to environment variable value
static void copy_env_value(char* dest, const char* src, size_t dest_size)
{
    strncpy(dest, src, dest_size - 1);
    dest[dest_size - 1] = '\0';
}

// Strong implementation of Dmod_SetEnv for embedded system
bool Dmod_SetEnv(const char* name, const char* value)
{
    if(name == NULL || value == NULL || name[0] == '\0' || value[0] == '\0')
        return false;
        
    // Check if variable already exists
    for(int i = 0; i < g_envVarCount; i++)
    {
        if(strcmp(g_envVars[i].name, name) == 0)
        {
            // Update existing variable
            copy_env_value(g_envVars[i].value, value, ENV_VALUE_SIZE);
            return true;
        }
    }
    
    // Add new variable
    if(g_envVarCount < MAX_ENV_VARS)
    {
        copy_env_value(g_envVars[g_envVarCount].name, name, ENV_NAME_SIZE);
        copy_env_value(g_envVars[g_envVarCount].value, value, ENV_VALUE_SIZE);
        g_envVarCount++;
        return true;
    }
    
    return false;
}

// Strong implementation of Dmod_GetEnv for embedded system
const char* Dmod_GetEnv(const char* name)
{
    if(name == NULL)
        return NULL;
        
    for(int i = 0; i < g_envVarCount; i++)
    {
        if(strcmp(g_envVars[i].name, name) == 0)
        {
            return g_envVars[i].value;
        }
    }
    
    return NULL;
}

// Simple helper to convert integer to hex string
static void uint_to_hex_str(unsigned int value, char* buffer, size_t buffer_size)
{
    const char* hex_digits = "0123456789ABCDEF";
    char temp[16];
    int i = 0;
    
    // Need at least 4 bytes for "0x0\0"
    if(buffer_size < 4)
    {
        if(buffer_size > 0) buffer[0] = '\0';
        return;
    }
    
    if(value == 0)
    {
        buffer[0] = '0';
        buffer[1] = 'x';
        buffer[2] = '0';
        buffer[3] = '\0';
        return;
    }
    
    // Convert to hex digits (reverse order)
    while(value > 0 && i < 15)
    {
        temp[i++] = hex_digits[value & 0xF];
        value >>= 4;
    }
    
    // Build final string with "0x" prefix
    buffer[0] = '0';
    buffer[1] = 'x';
    int j = 2;
    while(i > 0 && j < (int)buffer_size - 1)
    {
        buffer[j++] = temp[--i];
    }
    buffer[j] = '\0';
}

// Simple helper to convert integer to decimal string
static void uint_to_dec_str(unsigned int value, char* buffer, size_t buffer_size)
{
    char temp[16];
    int i = 0;
    
    // Need at least 2 bytes for "0\0"
    if(buffer_size < 2)
    {
        if(buffer_size > 0) buffer[0] = '\0';
        return;
    }
    
    if(value == 0)
    {
        buffer[0] = '0';
        buffer[1] = '\0';
        return;
    }
    
    // Convert to decimal digits (reverse order)
    while(value > 0 && i < 15)
    {
        temp[i++] = '0' + (value % 10);
        value /= 10;
    }
    
    // Reverse to get correct order
    int j = 0;
    while(i > 0 && j < (int)buffer_size - 1)
    {
        buffer[j++] = temp[--i];
    }
    buffer[j] = '\0';
}

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

    if(!dmvfs_init(DMBOOT_MAX_MOUNT_POINTS, DMBOOT_MAX_OPEN_FILES))
    {
        DMOD_LOG_ERROR("VFS initialization failed!\n");
        while(1);
    }

    // Load startup.dmp if provided
    void* startup_dmp_start = (void*)&__startup_dmp_start__;
    void* startup_dmp_end = (void*)&__startup_dmp_end__;
    size_t startup_dmp_size = (size_t)((uintptr_t)startup_dmp_end - (uintptr_t)startup_dmp_start);
    
    if(startup_dmp_size > 0)
    {
        DMOD_LOG_INFO("Loading startup.dmp: Start=0x%X, Size=%u bytes\n", 
                     (uintptr_t)startup_dmp_start, (unsigned int)startup_dmp_size);
        
        uint32_t packageIndex = 0;
        if(Dmod_AddPackageBuffer(startup_dmp_start, startup_dmp_size, &packageIndex))
        {
            DMOD_LOG_INFO("Startup package loaded successfully, index=%u\n", (unsigned int)packageIndex);
        }
        else
        {
            DMOD_LOG_ERROR("Failed to load startup package\n");
        }
    }
    else
    {
        DMOD_LOG_INFO("No startup.dmp provided\n");
    }

    // Set user_data environment variables
    void* user_data_start = (void*)&__user_data_start__;
    void* user_data_end = (void*)&__user_data_end__;
    size_t user_data_size = (size_t)((uintptr_t)user_data_end - (uintptr_t)user_data_start);
    
    if(user_data_size > 0)
    {
        DMOD_LOG_INFO("User data: Start=0x%X, Size=%u bytes\n", 
                     (uintptr_t)user_data_start, (unsigned int)user_data_size);
        
        // Set environment variables for user_data using Dmod_SetEnv
        char addr_str[32];
        char size_str[32];
        uint_to_hex_str((unsigned int)(uintptr_t)user_data_start, addr_str, sizeof(addr_str));
        uint_to_dec_str((unsigned int)user_data_size, size_str, sizeof(size_str));
        
        Dmod_SetEnv("USER_DATA_ADDR", addr_str);
        Dmod_SetEnv("USER_DATA_SIZE", size_str);
        
        DMOD_LOG_INFO("Environment variables set: USER_DATA_ADDR=%s, USER_DATA_SIZE=%s\n", addr_str, size_str);
    }
    else
    {
        DMOD_LOG_INFO("No user_data provided\n");
    }

    int i = 0;
    while(1)
    {
        DMOD_LOG_INFO("Waiting for better times... ID: %d\n", i++);
        delay(1000000);
    }
    return 0;
}