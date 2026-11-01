#include <string.h>
#include "dmsel_port_host.h"

static int h_erase( void* user, uint32_t offset, uint32_t size )
{
    host_flash_t* f = (host_flash_t*)user;
    if( offset + size > HOST_FLASH_SIZE )
    {
        return -1;
    }
    memset( f->flash + offset, 0xFF, size );
    f->erases++;
    return 0;
}

static int h_program( void* user, uint32_t offset, const void* data, uint32_t size )
{
    host_flash_t* f = (host_flash_t*)user;
    uint32_t i;
    const uint8_t* d = (const uint8_t*)data;

    if( offset % 4 != 0 || size % 4 != 0 || offset + size > HOST_FLASH_SIZE )
    {
        return -1;
    }
    if( f->fail_after >= 0 && f->programs >= f->fail_after )
    {
        // The power goes in the middle: a half of the words are written
        for( i = 0; i < size / 2 / 4 * 4; i++ )
        {
            f->flash[offset + i] &= d[i];
        }
        f->programs++;
        return -1;
    }
    for( i = 0; i < size; i += 4 )
    {
        uint32_t k;
        for( k = 0; k < 4; k++ )
        {
            if( f->flash[offset + i + k] != 0xFF )
            {
                f->program_errors++;
                return -1;
            }
        }
    }
    memcpy( f->flash + offset, d, size );
    f->programs++;
    return 0;
}

static void h_jump( void* user, uint32_t vector_address )
{
    ((host_flash_t*)user)->jumped_to = vector_address;
}

static void h_watchdog( void* user, uint32_t ms )
{
    ((host_flash_t*)user)->watchdog_ms = ms;
}

static void h_log( void* user, const char* text )
{
    host_flash_t* f = (host_flash_t*)user;
    size_t n = strlen( f->log );
    if( n + strlen( text ) + 1 < sizeof(f->log) )
    {
        strcpy( f->log + n, text );
    }
}

void host_flash_init( host_flash_t* f )
{
    memset( f, 0, sizeof(*f) );
    memset( f->flash, 0xFF, sizeof(f->flash) );
    f->fail_after = -1;
    f->port.flash = f->flash;
    f->port.erase = h_erase;
    f->port.program = h_program;
    f->port.jump = h_jump;
    f->port.log = h_log;
    f->port.watchdog_start = h_watchdog;
    f->port.user = f;
}
