/**
 * @file main.c
 * @brief A test image of a bank for the ESP32-S3: proves that the selector brought the image into the memory of the chip
 *        (the code runs from the flash, XIP; the read-only data are read from the flash; the data and a function are copied
 *        to the RAM) and that the table of the selector works from the firmware. Reports on the USB-Serial/JTAG.
 *
 * One build for both banks: the bank it runs from is asked of the selector (DMSEL_RUNNING_STARTED).
 */
#include <stdint.h>
#include "dmsel_table.h"

#define REG(a)                  (*(volatile uint32_t*)(a))
#define USB_EP1                 REG( 0x60038000u )
#define USB_EP1_CONF            REG( 0x60038004u )
#define EP1_WR_DONE             (1u << 0)
#define EP1_IN_FREE             (1u << 1)
#define IMAGE_DATA_WINDOW       0x3D000000u

extern void ets_delay_us( uint32_t us );

static int g_absent;

static int put_byte( char c )
{
    unsigned i;

    if( !(USB_EP1_CONF & EP1_IN_FREE) )
    {
        USB_EP1_CONF = EP1_WR_DONE;
        for( i = 0; i < 2000 && !(USB_EP1_CONF & EP1_IN_FREE); i++ ) ets_delay_us( 10 );
        if( !(USB_EP1_CONF & EP1_IN_FREE) ) return 0;
    }
    USB_EP1 = (uint8_t)c;
    return 1;
}

static void out( const char* text )
{
    if( g_absent && !(USB_EP1_CONF & EP1_IN_FREE) ) return;
    g_absent = 0;
    for( ; *text != 0; text++ )
    {
        if( (*text == '\n' && !put_byte( '\r' )) || !put_byte( *text ) ) { g_absent = 1; return; }
    }
    USB_EP1_CONF = EP1_WR_DONE;
}

static void out_hex( const char* label, uint32_t value )
{
    char text[40];
    unsigned n = 0, i;

    while( *label != 0 && n < 24 ) text[n++] = *label++;
    text[n++] = '0'; text[n++] = 'x';
    for( i = 0; i < 8; i++ ) text[n++] = "0123456789abcdef"[(value >> (28 - 4 * i)) & 0xF];
    text[n++] = '\n'; text[n] = 0;
    out( text );
}

static void out_dec( const char* label, int32_t value )
{
    char text[40], digits[12];
    unsigned n = 0, d = 0;
    uint32_t v = value < 0 ? (uint32_t)(-(int64_t)value) : (uint32_t)value;

    while( *label != 0 && n < 24 ) text[n++] = *label++;
    if( value < 0 ) text[n++] = '-';
    do { digits[d++] = (char)('0' + v % 10); v /= 10; } while( v != 0 );
    while( d != 0 ) text[n++] = digits[--d];
    text[n++] = '\n'; text[n] = 0;
    out( text );
}

static uint32_t crc32( const volatile uint8_t* p, uint32_t n )
{
    uint32_t crc = 0xFFFFFFFFu, i, b;

    for( i = 0; i < n; i++ )
    {
        crc ^= p[i];
        for( b = 0; b < 8; b++ ) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

const char g_rodata[] = "fw: a string from the flash, read through the data bus\n";     // .rodata
volatile uint32_t g_data = 0x12345678u;                                                  // .data (copied)
static uint32_t g_bss_zero;                                                               // .bss: the start clears it
static uint8_t g_scratch[0x8000] __attribute__(( aligned( 8 ) ));
static dmsel_t g_state;

/** Runs from the RAM (copied from the image by the start) */
__attribute__(( section( ".iram.text" ), noinline )) uint32_t iram_mix( uint32_t a, uint32_t b )
{
    return (a * 31u) ^ (b + 7u);
}

static void report_banks( const dmsel_table_t* t )
{
    dmsel_bank_info_t info;
    int b;

    out_dec( "fw: banks            ", t->bank_count( &g_state ) );
    out_dec( "fw: running bank     ", t->running_bank( &g_state ) );
    for( b = 0; b < t->bank_count( &g_state ); b++ )
    {
        info.struct_size = sizeof(info);
        t->get_info( &g_state, b, &info );
        out_dec( "fw:   bank           ", b );
        out_dec( "fw:     state        ", (int32_t)info.state );
        out_dec( "fw:     version      ", (int32_t)info.version );
        out_dec( "fw:     tries        ", (int32_t)info.tries );
    }
}

int main( void )
{
    const dmsel_table_t* t = (const dmsel_table_t*)DMSEL_TABLE_ADDRESS;
    const volatile uint32_t* header = (const volatile uint32_t*)IMAGE_DATA_WINDOW;
    uint32_t n = 0, size, version, hdr_size, i;
    static uint8_t copy[64];
    uint32_t counter = 0;

    out( "\nfw: started\n" );
    out_hex( "fw: main runs at     ", (uint32_t)(uintptr_t)&main );         // 0x43...: XIP
    out( g_rodata );
    out_hex( "fw: rodata is at     ", (uint32_t)(uintptr_t)g_rodata );      // 0x3D...
    out_hex( "fw: .data (copied)   ", g_data );                             // 0x12345678
    out_hex( "fw: .bss             ", g_bss_zero );                         // the start clears it: 0
    out_hex( "fw: iram function at ", (uint32_t)(uintptr_t)&iram_mix );     // 0x4037...
    out_hex( "fw: iram function    ", iram_mix( 1, 2 ) );                   // (31)^(9) = 22 = 0x16

    // The header of this image through the data window (dmsel_header_t), and the CRC of the image by the firmware itself
    hdr_size = header[1] >> 16;
    size = header[2];
    version = header[3];
    out_hex( "fw: header magic     ", header[0] );                          // "DMBK"
    out_dec( "fw: image size       ", (int32_t)size );
    out_dec( "fw: image version    ", (int32_t)version );
    out_hex( "fw: image crc (calc) ", crc32( (const volatile uint8_t*)IMAGE_DATA_WINDOW + hdr_size, size - hdr_size ) );
    out_hex( "fw: image crc (hdr)  ", header[4] );

    // The table of the selector
    out_hex( "fw: table magic      ", t->magic );
    if( t->magic == DMSEL_TABLE_MAGIC )
    {
        out_dec( "fw: table init       ", t->init( &g_state, DMSEL_RUNNING_STARTED, g_scratch ) );
        report_banks( t );
        out_dec( "fw: persist write    ", t->persist_write( &g_state, 0x5445u, "esp32s3", 8 ) );
        out_dec( "fw: persist read     ", t->persist_read( &g_state, 0x5445u, copy, sizeof(copy) ) );
        out( "fw: persist value    " );
        out( (const char*)copy );
        out( "\n" );
        out_dec( "fw: ready            ", t->ready( &g_state ) );
        report_banks( t );
    }

    for( ;; )
    {
        for( i = 0; i < 10; i++ ) ets_delay_us( 100000 );
        out_dec( "fw: alive            ", (int32_t)++counter );
        n += iram_mix( n, counter );
    }
}
