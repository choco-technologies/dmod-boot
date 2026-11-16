/**
 * @brief Test application that crashes on purpose (see README.md)
 */
#include "dmod.h"
#include <stdint.h>
#include <string.h>

/* An address nothing answers at: in the reserved part of the memory map of a Cortex-M, and in the gap of the one of the
 * ESP32-S3 (0x30000000 is mapped there, as an alias) */
#if defined( __XTENSA__ )
#define UNMAPPED_ADDRESS    0x10000000UL
#else
#define UNMAPPED_ADDRESS    0x30000000UL
#endif

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
 * @brief Recurse forever, calling into the firmware at every level
 *
 * The firmware runs on the stack of the caller: with the allocator and the log called at every level, the
 * stack runs out while it is in use by the firmware as well as by the code of the application, and the process
 * is taken down with the heap and the log in whatever state that left them.
 *
 * @param depth Current depth of the recursion
 * @return uint32_t A value nobody is ever going to see
 */
static uint32_t __attribute__(( noinline )) exhaust_stack_in_firmware( uint32_t depth )
{
    volatile uint8_t frame[ 16 + ( RECURSION_FRAME_SIZE * ( depth % 3 ) ) / 8 ];

    frame[ 0 ] = (uint8_t)depth;
    void* memory = Dmod_Malloc( 16 );
    Dmod_Free( memory );
    Dmod_Printf( "" );
    return exhaust_stack_in_firmware( depth + 1 ) + frame[ 0 ];
}

/**
 * @brief Execute an instruction the CPU does not have
 */
static void execute_undefined_instruction( void )
{
#if defined( __arm__ )
    __asm volatile ( "udf #0" );
#elif defined( __XTENSA__ )
    /* (__builtin_trap() is a BREAK there: a debug exception, not an illegal instruction) */
    __asm volatile ( "ill" );
#else
    __builtin_trap();
#endif
}

/**
 * @brief Read from an address nothing is mapped at
 *
 * @return uint32_t What the read returned, if it returned
 */
static uint32_t read_unmapped_address( uintptr_t address )
{
    return *(volatile uint32_t*)address;
}

/**
 * @brief Parse a hexadecimal number
 *
 * @param text The number, with or without 0x
 * @return uintptr_t The value (0 for an empty or invalid text)
 */
static uintptr_t parse_hex( const char* text )
{
    uintptr_t value = 0;

    if( text[ 0 ] == '0' && ( text[ 1 ] == 'x' || text[ 1 ] == 'X' ) )
    {
        text += 2;
    }
    for( ; *text != '\0'; text++ )
    {
        const char c = *text;
        const unsigned digit = ( c >= '0' && c <= '9' ) ? (unsigned)( c - '0' )
                             : ( c >= 'a' && c <= 'f' ) ? (unsigned)( c - 'a' + 10 )
                             : ( c >= 'A' && c <= 'F' ) ? (unsigned)( c - 'A' + 10 ) : 16U;
        if( digit == 16U )
        {
            return 0;
        }
        value = ( value << 4 ) | digit;
    }
    return value;
}

/**
 * @brief Jump to where the CPU cannot execute from
 *
 * On a Cortex-M an address without the Thumb bit, which switches the CPU to a state it does not have; on an Xtensa an
 * address nothing is mapped at (a failed fetch of an instruction).
 */
static void jump_to_arm_state( void )
{
#if defined( __XTENSA__ )
    void ( *target )( void ) = (void ( * )( void ))UNMAPPED_ADDRESS;
#else
    void ( *target )( void ) = (void ( * )( void ))0x08000000UL;
#endif
    target();
}

static void print_usage( void )
{
    Dmod_Printf( "Usage: faulttest undef|state|access [hex address]|stack|stackfw|ok\n" );
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
        const uintptr_t address = argc > 2 ? parse_hex( argv[ 2 ] ) : UNMAPPED_ADDRESS;
        Dmod_Printf( "Reading 0x%08lX...\n", (unsigned long)address );
        Dmod_Printf( "Read 0x%08lX\n", (unsigned long)read_unmapped_address( address ) );
    }
    else if( strcmp( argv[ 1 ], "stack" ) == 0 )
    {
        Dmod_Printf( "Exhausting the stack...\n" );
        Dmod_Printf( "Recursion returned %lu\n", (unsigned long)exhaust_stack( 0 ) );
    }
    else if( strcmp( argv[ 1 ], "stackfw" ) == 0 )
    {
        Dmod_Printf( "Exhausting the stack in the firmware...\n" );
        Dmod_Printf( "Recursion returned %lu\n", (unsigned long)exhaust_stack_in_firmware( 0 ) );
    }
    else if( strcmp( argv[ 1 ], "ok" ) != 0 )
    {
        print_usage();
        return 1;
    }

    Dmod_Printf( "faulttest: still alive\n" );
    return 0;
}
