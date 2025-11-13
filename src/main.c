#include <string.h>
#include "dmod.h"
#include "dmlog.h"
#include "dmheap.h"
#include "dmvfs.h"
#include "dmenv.h"

extern void* __logs_start__;
extern void* __logs_end__;
extern void* __dmod_inputs_start;
extern void* __dmod_inputs_end;
extern void* __heap_start__;
extern void* __heap_end__;
extern void* __startup_dmp_start;
extern void* __startup_dmp_end;
extern void* __startup_dmp_size;
extern void* __user_data_start;
extern void* __user_data_end;
extern void* __user_data_size;

int my_global_var = 42;

void delay(int cycles)
{
    for(volatile int i = 0; i < cycles; i++);
}

void HardFault_Handler(void)
{
    DMOD_LOG_ERROR("HardFault_Handler invoked!\n");
    while(1);
}

static void load_embedded_startup_dmp(void)
{
    void* startup_dmp_start = &__startup_dmp_start;
    void* startup_dmp_end   = &__startup_dmp_end;
    size_t startup_dmp_size = (size_t)((uintptr_t)startup_dmp_end - (uintptr_t)startup_dmp_start);
    if(startup_dmp_size > 0)
    {
        DMOD_LOG_INFO("Loading startup.dmp from ROM: addr=0x%X, size=%u bytes\n", 
                      (uintptr_t)startup_dmp_start, (unsigned int)startup_dmp_size);
        
        Dmod_Context_t* startup_ctx = Dmod_Load(startup_dmp_start, startup_dmp_size);
        if(startup_ctx != NULL)
        {
            DMOD_LOG_INFO("Startup package loaded successfully\n");

            // Check module type and handle accordingly
            Dmod_ModuleType_t moduleType = Dmod_GetModuleType( startup_ctx );
            if( moduleType == Dmod_ModuleType_Library )
            {
                if( !Dmod_Enable( startup_ctx, false, NULL ) )
                {
                    DMOD_LOG_ERROR("Failed to start application module\n");
                }
            }
            else if( moduleType == Dmod_ModuleType_Application )
            {
                DMOD_LOG_INFO("Startup module is an application module\n");
                char argv0[] = "startup.dmp";
                char* argv[] = { argv0 };
                int argc = 1;
                if( Dmod_Run(startup_ctx, argc, argv) != 0 )
                {
                    DMOD_LOG_ERROR("Failed to run application module\n");
                }
            }
            else
            {
                DMOD_LOG_ERROR("Startup module has unknown module type: %d\n", moduleType);
            }
        }
        else
        {
            DMOD_LOG_ERROR("Failed to load startup.dmp package\n");
        }
    }
    else
    {
        DMOD_LOG_INFO("No startup.dmp embedded in ROM\n");
    }
}

static void setup_embedded_user_data(dmenv_ctx_t dmenv_ctx)
{
    size_t user_data_size = (size_t)(uintptr_t)&__user_data_size;
    if(user_data_size > 0)
    {
        void* user_data_start = &__user_data_start;
        DMOD_LOG_INFO("User data found in ROM: addr=0x%X, size=%u bytes\n", 
                      (uintptr_t)user_data_start, (unsigned int)user_data_size);
        
        dmenv_seti(dmenv_ctx, "USER_DATA_ADDR", (uint32_t)(uintptr_t)user_data_start);
        dmenv_seti(dmenv_ctx, "USER_DATA_SIZE", (uint32_t)user_data_size);
    }
    else
    {
        DMOD_LOG_INFO("No user_data embedded in ROM\n");
    }
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

    dmenv_ctx_t dmenv_ctx = dmenv_create(NULL);
    if(dmenv_ctx == NULL)
    {
        DMOD_LOG_ERROR("DMEnv initialization failed!\n");
        while(1);
    }
    dmenv_set_as_default(dmenv_ctx);

    if(!Dmod_Initialize())
    {
        DMOD_LOG_ERROR("DMOD initialization failed!\n");
        while(1);
    }

    Dmod_Printf("Global variable my_global_var = %d\n", my_global_var);

    if(!dmvfs_init(DMBOOT_MAX_MOUNT_POINTS, DMBOOT_MAX_OPEN_FILES))
    {
        DMOD_LOG_ERROR("VFS initialization failed!\n");
        while(1);
    }

    dmenv_set(dmenv_ctx, "DMOD_VERSION", DMOD_VERSION_STRING);
    dmenv_set(dmenv_ctx, "DMBOOT_MCU_NAME", DMBOOT_MCU_NAME_STRING);
    dmenv_set(dmenv_ctx, "DMBOOT_MCU_SERIES", DMBOOT_MCU_SERIES_STRING);
    dmenv_seti(dmenv_ctx, "DMBOOT_MAX_MOUNT_POINTS", DMBOOT_MAX_MOUNT_POINTS);
    dmenv_set(dmenv_ctx, "DMOD_REPO_DIR", DMOD_REPO_DIR);
    dmenv_set(dmenv_ctx, "DMOD_REPO_PATHS", DMOD_REPO_PATHS);
    
    // Set user_data environment variables if embedded in ROM
    setup_embedded_user_data(dmenv_ctx);

    // Load startup.dmp if embedded in ROM
    load_embedded_startup_dmp();

    return 0;
}