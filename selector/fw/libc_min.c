/**
 * @file libc_min.c
 * @brief The few functions of the C library that the selector uses (it is linked without one)
 */
#include <stddef.h>
#include <stdint.h>

#define NO_PATTERNS __attribute__(( optimize( "no-tree-loop-distribute-patterns" ) ))

NO_PATTERNS void* memcpy( void* dst, const void* src, size_t n )
{
    uint8_t* d = dst; const uint8_t* s = src;
    while( n-- ) *d++ = *s++;
    return dst;
}

NO_PATTERNS void* memmove( void* dst, const void* src, size_t n )
{
    uint8_t* d = dst; const uint8_t* s = src;
    if( d < s ) { while( n-- ) *d++ = *s++; }
    else { d += n; s += n; while( n-- ) *--d = *--s; }
    return dst;
}

NO_PATTERNS void* memset( void* dst, int c, size_t n )
{
    uint8_t* d = dst;
    while( n-- ) *d++ = (uint8_t)c;
    return dst;
}

NO_PATTERNS int memcmp( const void* a, const void* b, size_t n )
{
    const uint8_t *x = a, *y = b;
    while( n-- ) { if( *x != *y ) return *x - *y; x++; y++; }
    return 0;
}

NO_PATTERNS size_t strlen( const char* s )
{
    size_t n = 0;
    while( s[n] ) n++;
    return n;
}

NO_PATTERNS char* strncpy( char* dst, const char* src, size_t n )
{
    size_t i = 0;
    for( ; i < n && src[i]; i++ ) dst[i] = src[i];
    for( ; i < n; i++ ) dst[i] = 0;
    return dst;
}
