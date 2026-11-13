/**
 * @brief Test application that crashes on purpose (see README.md)
 */
#include "dmod.h"
#include <stdint.h>
#include <string.h>

/* An address in the reserved part of the memory map of a Cortex-M: nothing answers there */
#define UNMAPPED_ADDRESS    0x30000000UL

/* Size of the frame each level of the recursion takes */
#define RECURSION_FRAME_SIZE    128

/**
 * @brief Recurse forever, using stack at every level
 *
 * The buffer is written and read back so the compiler has to keep the
 * frame, and the result depends on the call below so the recursion cannot
 * be turned into a loop.
 *
 * @param depth Current depth of the recursion
 * @return uint32_t A value nobody is ever going to see
 */
static uint32_t __attribute__(( noinline )) exhaust_stack( uint32_t depth )
{
    volatile uint8_t frame[ RECURSION_FRAME_SIZE ];

    memset( (void*)frame, (int)depth, sizeof( frame ) );
    return exhaust_stack( depth + 1 ) + frame[ depth % sizeof( frame ) ];
}

/**
 * @brief Execute an instruction the CPU does not have
 */
static void execute_undefined_instruction( void )
{
#if defined( __arm__ )
    __asm volatile ( "udf #0" );
#else
    __builtin_trap();
#endif
}

/**
 * @brief Read from an address nothing is mapped at
 *
 * @return uint32_t What the read returned, if it returned
 */
static uint32_t read_unmapped_address( void )
{
    return *(volatile uint32_t*)UNMAPPED_ADDRESS;
}

/**
 * @brief Jump to an address without the Thumb bit, which switches the CPU to a state it does not have
 */
static void jump_to_arm_state( void )
{
    void ( *target )( void ) = (void ( * )( void ))0x08000000UL;
    target();
}

static void print_usage( void )
{
    Dmod_Printf( "Usage: faulttest undef|state|access|stack|ok\n" );
}

int main( int argc, char* argv[] )
{
    if( argc < 2 )
    {
        print_usage();
        return 1;
    }

    if( strcmp( argv[ 1 ], "undef" ) == 0 )
    {
        Dmod_Printf( "Executing an undefined instruction...\n" );
        execute_undefined_instruction();
    }
    else if( strcmp( argv[ 1 ], "state" ) == 0 )
    {
        Dmod_Printf( "Switching to a state the CPU does not have...\n" );
        jump_to_arm_state();
    }
    else if( strcmp( argv[ 1 ], "access" ) == 0 )
    {
        Dmod_Printf( "Reading 0x%08lX...\n", (unsigned long)UNMAPPED_ADDRESS );
        Dmod_Printf( "Read 0x%08lX\n", (unsigned long)read_unmapped_address() );
    }
    else if( strcmp( argv[ 1 ], "stack" ) == 0 )
    {
        Dmod_Printf( "Exhausting the stack...\n" );
        Dmod_Printf( "Recursion returned %lu\n", (unsigned long)exhaust_stack( 0 ) );
    }
    else if( strcmp( argv[ 1 ], "ok" ) != 0 )
    {
        print_usage();
        return 1;
    }

    Dmod_Printf( "faulttest: still alive\n" );
    return 0;
}
