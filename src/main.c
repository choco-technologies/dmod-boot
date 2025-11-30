// #define DMOD_ENABLE_REGISTRATION
#include <string.h>
#include "dmod.h"
#include "dmlog.h"
#include "dmheap.h"
#include "dmvfs.h"
#include "dmenv.h"
#include "dmlist.h"

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
extern void* __modules_dmp_start;
extern void* __modules_dmp_end;
extern void* __modules_dmp_size;

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

/**
 * @brief Read module name from input command
 * 
 * @param input Input command string
 * @param module_name Buffer to store the module name
 * @param module_name_size Size of the module name buffer
 * 
 * @return true if module name was read successfully, false otherwise
 */
static bool read_module_name_from_input(const char* input, char* module_name, size_t module_name_size)
{
    while(*input != ' ') input++; // Skip leading spaces
    while(*input == ' ') input++; // Skip leading spaces

    const char* name_start = input;
    size_t name_len = strcspn(name_start, "\n");
    if(name_len == 0 || name_len >= module_name_size)
    {
        return false;
    }

    strncpy(module_name, name_start, name_len);
    module_name[name_len] = '\0';
    return true;
}

/**
 * @brief Prepare argv array from input command
 * 
 * @param input Input command string
 * @param argv_out Pointer to store the allocated argv array
 * @param argc_out Pointer to store the argument count
 * @param module_name Buffer to store the module name
 * @param module_name_len Size of the module name buffer
 * 
 * @return true if argv was prepared successfully, false otherwise
 */
static bool prepare_argv_for_run(const char* input, char*** argv_out, int* argc_out, char* module_name, size_t module_name_len)
{
    // skip command
    while(*input != ' ') input++; // Skip leading spaces
    while(*input == ' ') input++; // Skip leading spaces

    // Read module name
    const char* name_start = input;
    size_t name_len = strcspn(name_start, " \n");
    if(name_len == 0 || name_len >= module_name_len)
    {
        return false;
    }
    strncpy(module_name, name_start, name_len);
    module_name[name_len] = '\0';

    // Count arguments
    int argc = 0;
    const char* ptr = input;
    while(*ptr != '\0' && *ptr != '\n')
    {
        while(*ptr == ' ') ptr++;
        if(*ptr != '\0' && *ptr != '\n')
        {
            argc++;
            while(*ptr != ' ' && *ptr != '\0' && *ptr != '\n') ptr++;
        }
    }

    // Allocate argv array
    char** argv = (char**)Dmod_MallocEx(sizeof(char*) * argc, module_name);
    if(argv == NULL)
    {
        return false;
    }

    // Fill argv array
    ptr = input;
    int index = 0;
    while(*ptr != '\0' && *ptr != '\n' && index < argc)
    {
        while(*ptr == ' ') ptr++;
        if(*ptr != '\0' && *ptr != '\n')
        {
            const char* arg_start = ptr;
            while(*ptr != ' ' && *ptr != '\0' && *ptr != '\n') ptr++;
            size_t arg_len = (size_t)(ptr - arg_start);
            argv[index] = (char*)Dmod_MallocEx(arg_len + 1, module_name);
            if(argv[index] == NULL)
            {
                // Free previously allocated args
                for(int j = 0; j < index; j++)
                {
                    Dmod_FreeEx(argv[j], false);
                }
                Dmod_FreeEx(argv, false);
                return false;
            }
            strncpy(argv[index], arg_start, arg_len);
            argv[index][arg_len] = '\0';
            index++;
        }
    }

    *argv_out = argv;
    *argc_out = argc;
    return true;
}

static void start_main_module(Dmod_Context_t* main_ctx)
{
    Dmod_ModuleType_t moduleType = Dmod_GetModuleType( main_ctx );
    if( moduleType == Dmod_ModuleType_Library )
    {
        if( !Dmod_Enable( main_ctx, false, NULL ) )
        {
            DMOD_LOG_ERROR("Failed to enable modules library\n");
        }
    }
    else if( moduleType == Dmod_ModuleType_Application )
    {
        DMOD_LOG_INFO("Main module is an application module\n");
        char argv0[] = "main_module";
        char* argv[] = { argv0 };
        int argc = 1;
        if( Dmod_Run(main_ctx, argc, argv) != 0 )
        {
            DMOD_LOG_ERROR("Failed to run main application module\n");
        }
    }
    else
    {
        DMOD_LOG_ERROR("Main module is not an application module\n");
    }
}

static Dmod_Context_t* load_embedded_modules_dmp(void)
{
    Dmod_Context_t* context = NULL;
    void* modules_dmp_start = &__modules_dmp_start;
    void* modules_dmp_end   = &__modules_dmp_end;
    size_t modules_dmp_size = (size_t)((uintptr_t)modules_dmp_end - (uintptr_t)modules_dmp_start);
    if(modules_dmp_size > 0)
    {
        DMOD_LOG_INFO("Loading modules.dmp from ROM: addr=0x%X, size=%u bytes\n", 
                      (uintptr_t)modules_dmp_start, (unsigned int)modules_dmp_size);
        
        context = Dmod_Load(modules_dmp_start, modules_dmp_size);
        if(context == NULL)
        {
            DMOD_LOG_ERROR("Failed to load modules.dmp package\n");
        }
    }
    else
    {
        DMOD_LOG_INFO("No modules.dmp embedded in ROM\n");
    }
    return context;
}

static void setup_embedded_user_data(dmenv_ctx_t dmenv_ctx)
{
    void* user_data_start = &__user_data_start;
    void* user_data_end   = &__user_data_end;
    size_t user_data_size = (size_t)((uintptr_t)user_data_end - (uintptr_t)user_data_start);
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

static void mount_embedded_filesystems(void)
{
    dmvfs_mount_fs("dmramfs", "/", NULL);
}

int main(int argc, char** argv) 
{
    Dmod_SetLogLevel(Dmod_LogLevel_Info);
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
    dmenv_set_root_context(dmenv_ctx);

    if(!Dmod_Initialize())
    {
        DMOD_LOG_ERROR("DMOD initialization failed!\n");
        while(1);
    }

    if(!dmvfs_init(DMBOOT_MAX_MOUNT_POINTS, DMBOOT_MAX_OPEN_FILES))
    {
        DMOD_LOG_ERROR("VFS initialization failed!\n");
        while(1);
    }

    dmenv_set(dmenv_ctx, "HOSTNAME", DMBOOT_MCU_NAME_STRING);
    dmenv_set(dmenv_ctx, "DMOD_VERSION", DMOD_VERSION_STRING);
    dmenv_set(dmenv_ctx, "DMBOOT_MCU_NAME", DMBOOT_MCU_NAME_STRING);
    dmenv_set(dmenv_ctx, "DMBOOT_MCU_SERIES", DMBOOT_MCU_SERIES_STRING);
    dmenv_seti(dmenv_ctx, "DMBOOT_MAX_MOUNT_POINTS", DMBOOT_MAX_MOUNT_POINTS);
    dmenv_set(dmenv_ctx, "DMOD_REPO_DIR", DMOD_REPO_DIR);
    dmenv_set(dmenv_ctx, "DMOD_REPO_PATHS", DMOD_REPO_PATHS);
    dmenv_seti(dmenv_ctx, "DMBOOT_EMULATION", DMBOOT_EMULATION_ENABLED);
    
    // Set user_data environment variables if embedded in ROM
    setup_embedded_user_data(dmenv_ctx);
    
    // Load modules.dmp if embedded in ROM
    Dmod_Context_t* mainModule = load_embedded_modules_dmp();

    // Mount embedded filesystems
    mount_embedded_filesystems();

    // Load startup.dmp if embedded in ROM
    load_embedded_startup_dmp();

    // Start main module if loaded
    start_main_module(mainModule);
    
    Dmod_Printf("Entering interactive shell. Type 'help' for commands.\n");

    while(1)
    {
        dmlog_puts(ctx, "$ ");
        while(!dmlog_input_available(ctx))
        {
            dmlog_input_request(ctx, DMLOG_INPUT_REQUEST_FLAG_LINE_MODE);
            delay(1000);
        }
        char input_buffer[128];
        if(dmlog_input_gets(ctx, input_buffer, sizeof(input_buffer)))
        {
            if(strcmp(input_buffer, "help\n") == 0)
            {
                dmlog_puts(ctx, "Available commands:\n");
                dmlog_puts(ctx, "  help                       - Show this help message\n");
                dmlog_puts(ctx, "  version                    - Show DMOD version\n");
                dmlog_puts(ctx, "  load <module_name>         - Load module by name\n");
                dmlog_puts(ctx, "  unload <module_name>       - Unload module by name\n");
                dmlog_puts(ctx, "  run <module_name> args ... - Run application module by name\n");
                dmlog_puts(ctx, "  list                       - List loaded modules\n");
                dmlog_puts(ctx, "  clear                      - Clear the screen\n");
                dmlog_puts(ctx, "  exit                       - Exit the shell\n");
            }
            else if(strcmp(input_buffer, "version\n") == 0)
            {
                dmlog_puts(ctx, "DMOD Version: " DMOD_VERSION_STRING "\n");
            }
            else if(strcmp(input_buffer, "clear\n") == 0)
            {
                dmlog_puts(ctx, "\033[2J\033[H"); // ANSI escape codes to clear terminal
            }
            else if(strncmp(input_buffer, "load", 4) == 0)
            {
                char module_name[64];
                if(!read_module_name_from_input(input_buffer, module_name, sizeof(module_name)))
                {
                    dmlog_puts(ctx, "Usage: load <module_name>\n");
                    continue;
                }
                
                if(Dmod_LoadModuleByName(module_name))
                {
                    dmlog_puts(ctx, "Module loaded successfully.\n");
                }
                else
                {
                    dmlog_puts(ctx, "Failed to load module.\n");
                }
            }
            else if(strncmp(input_buffer, "unload", 6) == 0)
            {
                char module_name[64];
                if(!read_module_name_from_input(input_buffer, module_name, sizeof(module_name)))
                {
                    dmlog_puts(ctx, "Usage: unload <module_name>\n");
                    continue;
                }

                if(Dmod_UnloadModule(module_name, false))
                {
                    dmlog_puts(ctx, "Module unloaded successfully.\n");
                }
                else
                {
                    dmlog_puts(ctx, "Failed to unload module.\n");
                }
            }
            else if(strncmp(input_buffer, "run", 3) == 0)
            {
                if(strlen(input_buffer) <= 4 || input_buffer[3] != ' ')
                {
                    dmlog_puts(ctx, "Usage: run <module_name> args ...\n");
                    continue;
                }
                char module_name[64];
                char** run_argv = NULL;
                int run_argc = 0;
                if(!prepare_argv_for_run(input_buffer, &run_argv, &run_argc, module_name, sizeof(module_name)))
                {
                    dmlog_puts(ctx, "Failed to prepare arguments for run command.\n");
                    continue;
                }

                if(Dmod_RunModule(module_name, run_argc, run_argv) == 0)
                {
                    dmlog_puts(ctx, "Module ran successfully.\n");
                }
                else
                {
                    dmlog_puts(ctx, "Failed to run module.\n");
                }

                // Free allocated argv
                for(int i = 0; i < run_argc; i++)
                {
                    Dmod_FreeEx(run_argv[i], false);
                }
                Dmod_FreeEx(run_argv, false);

            }
            else if(strncmp(input_buffer, "list", 4) == 0)
            {
                DMOD_LOG_WARN("Listing loaded modules is not implemented yet.\n");
            }
            else if(strcmp(input_buffer, "exit\n") == 0)
            {
                dmlog_puts(ctx, "Exiting shell.\n");
                break;
            }
            else
            {
                Dmod_Printf("Unknown command: %s", input_buffer);
            }
        }
    }

    return 0;
}