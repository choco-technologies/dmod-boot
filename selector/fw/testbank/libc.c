#include <stddef.h>
#include <stdint.h>
#define NP __attribute__(( optimize( "no-tree-loop-distribute-patterns" ) ))
NP void* memcpy( void* d, const void* s, size_t n ) { uint8_t* a = d; const uint8_t* b = s; while( n-- ) *a++ = *b++; return d; }
NP void* memset( void* d, int c, size_t n ) { uint8_t* a = d; while( n-- ) *a++ = (uint8_t)c; return d; }
NP int memcmp( const void* x, const void* y, size_t n ) { const uint8_t *a = x, *b = y; while( n-- ) { if( *a != *b ) return *a - *b; a++; b++; } return 0; }
