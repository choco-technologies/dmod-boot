/**
 * @file test_selector.c
 * @brief The selector on the flash in RAM: the choice of the bank, the trial and its confirmation, damaged images, a lost
 *        state, the persistent items, the compaction of the store, power cuts
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "dmsel.h"
#include "dmsel_port_host.h"

static int g_checks, g_failures;
#define CHECK_EQ( a, e ) do { long long a_ = (long long)(a), e_ = (long long)(e); g_checks++; \
    if( a_ != e_ ) { g_failures++; printf( "  FAIL %s:%d: %s == %s (got %lld, expected %lld)\n", __FILE__, __LINE__, #a, #e, a_, e_ ); } } while( 0 )
#define CHECK( c ) do { g_checks++; if( !(c) ) { g_failures++; printf( "  FAIL %s:%d: %s\n", __FILE__, __LINE__, #c ); } } while( 0 )
#define RUN( t ) do { int b_ = g_failures; t(); printf( "%-4s %s\n", g_failures == b_ ? "ok" : "FAIL", #t ); } while( 0 )

#define FLASH_ADDRESS   0x08000000u
#define STORE_OFFSET    0x8000u
#define STORE_SIZE      0x8000u
#define BANK_A          0x20000u
#define BANK_B          0x80000u
#define BANK_SIZE       0x60000u

static host_flash_t g_f;
static uint8_t g_scratch[STORE_SIZE];
static dmsel_layout_t g_layout;
static dmsel_t g_s;

static void setup( void )
{
    host_flash_init( &g_f );
    memset( &g_layout, 0, sizeof(g_layout) );
    g_layout.flash_address = FLASH_ADDRESS;
    g_layout.store_offset = STORE_OFFSET;
    g_layout.store_size = STORE_SIZE;
    g_layout.bank_count = 2;
    g_layout.banks[0].offset = BANK_A;
    g_layout.banks[0].capacity = BANK_SIZE;
    g_layout.banks[1].offset = BANK_B;
    g_layout.banks[1].capacity = BANK_SIZE;
    g_layout.max_tries = 3;
    g_layout.watchdog_ms = 0;
}

/** The selector starts again after a reset: the flash stays, the RAM does not */
static void reset( void )
{
    g_f.jumped_to = 0;
    g_f.watchdog_ms = 0;
    g_f.fail_after = -1;
    CHECK_EQ( dmsel_init( &g_s, &g_layout, &g_f.port, g_scratch ), DMSEL_OK );
}

/** An image: header, vectors at 512, a body; written straight into the flash (as the update tool would) */
static void put_image( unsigned bank, uint32_t version, uint32_t size, uint8_t fill )
{
    uint8_t* base = g_f.flash + g_layout.banks[bank].offset;
    dmsel_header_t h;

    memset( base, 0xFF, size );
    memset( base + 512, fill, size - 512 );
    memset( &h, 0xFF, sizeof(h) );
    h.magic = DMSEL_HEADER_MAGIC;
    h.header_version = DMSEL_HEADER_VERSION;
    h.header_size = sizeof(h);
    h.image_size = size;
    h.version = version;
    h.image_crc = dmsel_crc32( 0, base + h.header_size, size - h.header_size );
    h.entry_offset = 512;
    h.flags = 0;
    h.header_crc = dmsel_crc32( 0, &h, sizeof(h) - 4 );
    memcpy( base, &h, sizeof(h) );
}

static uint32_t vector_of( unsigned bank )
{
    return FLASH_ADDRESS + g_layout.banks[bank].offset + 512;
}

static void test_crc( void )
{
    CHECK_EQ( dmsel_crc32( 0, "123456789", 9 ), 0xCBF43926u );
    CHECK_EQ( dmsel_crc32( dmsel_crc32( 0, "12345", 5 ), "6789", 4 ), 0xCBF43926u );
}

static void test_nothing_to_start( void )
{
    setup(); reset();
    CHECK_EQ( dmsel_choose( &g_s ), DMSEL_ERR_EMPTY );
    dmsel_boot( &g_s );
    CHECK_EQ( g_f.jumped_to, 0 );
    CHECK( strstr( g_f.log, "nothing to start" ) != NULL );
}

static void test_single_image_starts( void )
{
    setup(); put_image( 0, 5, 0x4000, 0xA5 ); reset();
    dmsel_boot( &g_s );
    CHECK_EQ( g_f.jumped_to, vector_of( 0 ) );
    CHECK_EQ( dmsel_running_bank( &g_s ), 0 );
    // And again after a reset: the state is in the store now
    reset();
    dmsel_boot( &g_s );
    CHECK_EQ( g_f.jumped_to, vector_of( 0 ) );
    CHECK( g_s.state_valid );
}

static void test_newest_image_without_a_state( void )
{
    setup(); put_image( 0, 5, 0x4000, 1 ); put_image( 1, 9, 0x5000, 2 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 1 );
    setup(); put_image( 0, 12, 0x4000, 1 ); put_image( 1, 9, 0x5000, 2 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
}

static void test_trial_confirmed( void )
{
    dmsel_bank_info_t info;

    setup(); put_image( 0, 1, 0x4000, 1 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    // The update: an image into B, verified, selected on trial
    put_image( 1, 2, 0x5000, 2 );
    CHECK_EQ( dmsel_select( &g_s, 1, 1 ), DMSEL_OK );
    reset();
    CHECK_EQ( dmsel_choose( &g_s ), 1 );
    info.struct_size = sizeof(info);
    CHECK_EQ( dmsel_get_info( &g_s, 1, &info ), DMSEL_OK );
    CHECK_EQ( info.state, DMSEL_BANK_TRIAL );
    CHECK_EQ( info.tries, 1 );
    CHECK_EQ( info.version, 2 );
    CHECK_EQ( info.address, FLASH_ADDRESS + BANK_B );
    // The firmware says it runs properly
    CHECK_EQ( dmsel_ready( &g_s ), DMSEL_OK );
    reset();
    CHECK_EQ( dmsel_choose( &g_s ), 1 );
    CHECK_EQ( dmsel_get_info( &g_s, 1, &info ), DMSEL_OK );
    CHECK_EQ( info.state, DMSEL_BANK_CONFIRMED );
    CHECK_EQ( info.tries, 0 );
}

static void test_trial_not_confirmed_goes_back( void )
{
    int i;

    setup(); put_image( 0, 1, 0x4000, 1 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    CHECK_EQ( dmsel_ready( &g_s ), DMSEL_OK );
    put_image( 1, 2, 0x5000, 2 );
    CHECK_EQ( dmsel_select( &g_s, 1, 1 ), DMSEL_OK );
    // Three starts without a word
    for( i = 0; i < 3; i++ )
    {
        reset();
        CHECK_EQ( dmsel_choose( &g_s ), 1 );
    }
    // The fourth: the image is dropped, the previous one runs
    reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    CHECK_EQ( g_s.state[1], DMSEL_BANK_INVALID );
    reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    CHECK_EQ( g_s.state[1], DMSEL_BANK_INVALID );
}

static void test_watchdog_only_for_a_trial( void )
{
    setup(); put_image( 0, 1, 0x4000, 1 ); put_image( 1, 2, 0x4000, 2 );
    g_layout.watchdog_ms = 5000; reset();
    dmsel_boot( &g_s );                                         // B, newest, not on trial
    CHECK_EQ( g_f.watchdog_ms, 0 );
    CHECK_EQ( dmsel_select( &g_s, 0, 1 ), DMSEL_OK );           // A on trial
    reset();
    dmsel_boot( &g_s );
    CHECK_EQ( g_f.jumped_to, vector_of( 0 ) );
    CHECK_EQ( g_f.watchdog_ms, 5000 );
}

static void test_permanent_select( void )
{
    setup(); put_image( 0, 1, 0x4000, 1 ); put_image( 1, 2, 0x4000, 2 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 1 );
    CHECK_EQ( dmsel_select( &g_s, 0, 0 ), DMSEL_OK );          // back to A for good
    reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    CHECK_EQ( g_s.state[0], DMSEL_BANK_CONFIRMED );
}

static void test_damaged_image_falls_back( void )
{
    setup(); put_image( 0, 1, 0x4000, 1 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    CHECK_EQ( dmsel_ready( &g_s ), DMSEL_OK );
    put_image( 1, 2, 0x5000, 2 );
    CHECK_EQ( dmsel_select( &g_s, 1, 1 ), DMSEL_OK );
    g_f.flash[BANK_B + 0x1234] ^= 0x10;                         // a bit flips in the selected image
    reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    CHECK_EQ( g_s.state[1], DMSEL_BANK_INVALID );

    // select() and verify() refuse such an image, and an empty bank
    CHECK_EQ( dmsel_verify( &g_s, 1 ), DMSEL_ERR_BAD );
    CHECK_EQ( dmsel_select( &g_s, 1, 1 ), DMSEL_ERR_BAD );
    memset( g_f.flash + BANK_B, 0xFF, 0x6000 );
    CHECK_EQ( dmsel_verify( &g_s, 1 ), DMSEL_ERR_EMPTY );
    CHECK_EQ( dmsel_select( &g_s, 1, 0 ), DMSEL_ERR_EMPTY );
    CHECK_EQ( dmsel_select( &g_s, 2, 0 ), DMSEL_ERR_PARAM );
}

static void test_header_checks( void )
{
    dmsel_header_t h;

    setup(); reset();
    put_image( 0, 1, 0x4000, 7 );
    CHECK_EQ( dmsel_verify( &g_s, 0 ), DMSEL_OK );
    // A header that was changed: its CRC fails
    memcpy( &h, g_f.flash + BANK_A, sizeof(h) );
    h.version = 99;
    memcpy( g_f.flash + BANK_A, &h, sizeof(h) );
    CHECK_EQ( dmsel_verify( &g_s, 0 ), DMSEL_ERR_BAD );
    // An image bigger than the bank
    put_image( 0, 1, 0x4000, 7 );
    memcpy( &h, g_f.flash + BANK_A, sizeof(h) );
    h.image_size = BANK_SIZE + 4;
    h.header_crc = dmsel_crc32( 0, &h, sizeof(h) - 4 );
    memcpy( g_f.flash + BANK_A, &h, sizeof(h) );
    CHECK_EQ( dmsel_verify( &g_s, 0 ), DMSEL_ERR_BAD );
    // Vectors not at a multiple of 512
    put_image( 0, 1, 0x4000, 7 );
    memcpy( &h, g_f.flash + BANK_A, sizeof(h) );
    h.entry_offset = 100;
    h.header_crc = dmsel_crc32( 0, &h, sizeof(h) - 4 );
    memcpy( g_f.flash + BANK_A, &h, sizeof(h) );
    CHECK_EQ( dmsel_verify( &g_s, 0 ), DMSEL_ERR_BAD );
}

static void test_lost_state_is_rebuilt( void )
{
    setup(); put_image( 0, 1, 0x4000, 1 ); put_image( 1, 2, 0x4000, 2 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 1 );
    memset( g_f.flash + STORE_OFFSET, 0xFF, STORE_SIZE );       // the store is gone
    reset();
    CHECK( !g_s.state_valid );
    CHECK_EQ( dmsel_choose( &g_s ), 1 );
}

static void test_persistency( void )
{
    uint8_t buf[64];
    const char a[] = "first value", b[] = "second";

    setup(); reset();
    CHECK_EQ( dmsel_persist_read( &g_s, 7, NULL, 0 ), DMSEL_ERR_NOENT );
    CHECK_EQ( dmsel_persist_write( &g_s, 7, a, sizeof(a) ), DMSEL_OK );
    CHECK_EQ( dmsel_persist_read( &g_s, 7, NULL, 0 ), sizeof(a) );
    memset( buf, 0, sizeof(buf) );
    CHECK_EQ( dmsel_persist_read( &g_s, 7, buf, sizeof(buf) ), sizeof(a) );
    CHECK( memcmp( buf, a, sizeof(a) ) == 0 );
    // A smaller buffer: the size of the whole item, a part of the data
    memset( buf, 0, sizeof(buf) );
    CHECK_EQ( dmsel_persist_read( &g_s, 7, buf, 5 ), sizeof(a) );
    CHECK( memcmp( buf, a, 5 ) == 0 && buf[5] == 0 );
    // Replaced, another item beside it, both survive a reset
    CHECK_EQ( dmsel_persist_write( &g_s, 7, b, sizeof(b) ), DMSEL_OK );
    CHECK_EQ( dmsel_persist_write( &g_s, 8, a, sizeof(a) ), DMSEL_OK );
    reset();
    CHECK_EQ( dmsel_persist_read( &g_s, 7, buf, sizeof(buf) ), sizeof(b) );
    CHECK( memcmp( buf, b, sizeof(b) ) == 0 );
    CHECK_EQ( dmsel_persist_read( &g_s, 8, NULL, 0 ), sizeof(a) );
    // The same value again does not touch the flash
    {
        int before = g_f.programs;
        CHECK_EQ( dmsel_persist_write( &g_s, 7, b, sizeof(b) ), DMSEL_OK );
        CHECK_EQ( g_f.programs, before );
    }
    // Removed
    CHECK_EQ( dmsel_persist_write( &g_s, 7, NULL, 0 ), DMSEL_OK );
    CHECK_EQ( dmsel_persist_read( &g_s, 7, NULL, 0 ), DMSEL_ERR_NOENT );
    CHECK_EQ( dmsel_persist_write( &g_s, 99, NULL, 0 ), DMSEL_OK );     // nothing to remove: not an error
    // An empty item is an item
    CHECK_EQ( dmsel_persist_write( &g_s, 5, "", 0 ), DMSEL_OK );
    CHECK_EQ( dmsel_persist_read( &g_s, 5, NULL, 0 ), 0 );
    // Wrong arguments
    CHECK_EQ( dmsel_persist_write( &g_s, 1, NULL, 4 ), DMSEL_ERR_PARAM );
    CHECK_EQ( dmsel_persist_read( &g_s, 8, NULL, 4 ), DMSEL_ERR_PARAM );
}

static void test_store_is_compacted( void )
{
    uint8_t value[100], buf[100];
    int i, erases_before;

    setup(); put_image( 0, 1, 0x4000, 1 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    CHECK_EQ( dmsel_persist_write( &g_s, 1000, "keep", 5 ), DMSEL_OK );
    erases_before = g_f.erases;
    // Far more than the sector holds: the same item over and over
    for( i = 0; i < 1000; i++ )
    {
        memset( value, i & 0xFF, sizeof(value) );
        value[0] = (uint8_t)i; value[1] = (uint8_t)(i >> 8);
        CHECK_EQ( dmsel_persist_write( &g_s, 1, value, sizeof(value) ), DMSEL_OK );
    }
    CHECK( g_f.erases > erases_before );
    reset();
    CHECK_EQ( dmsel_persist_read( &g_s, 1, buf, sizeof(buf) ), sizeof(value) );
    CHECK( memcmp( buf, value, sizeof(value) ) == 0 );
    CHECK_EQ( dmsel_persist_read( &g_s, 1000, buf, sizeof(buf) ), 5 );
    CHECK( memcmp( buf, "keep", 5 ) == 0 );
    // The state of the banks went through the compactions too
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    CHECK_EQ( g_s.state[0], DMSEL_BANK_VALID );
    CHECK_EQ( g_f.program_errors, 0 );
}

static void test_item_too_big( void )
{
    static uint8_t big[STORE_SIZE];

    setup(); reset();
    CHECK_EQ( dmsel_persist_write( &g_s, 1, big, STORE_SIZE ), DMSEL_ERR_NOSPACE );
    CHECK_EQ( dmsel_persist_write( &g_s, 1, big, STORE_SIZE - 100 ), DMSEL_OK );    // fits with a short state record
}

static void test_power_cut_while_writing( void )
{
    int cut;
    uint8_t buf[32];

    // A cut at every program of an update of the store: the older values stay readable, the store goes on working
    for( cut = 0; cut < 6; cut++ )
    {
        setup(); put_image( 0, 1, 0x4000, 1 ); reset();
        CHECK_EQ( dmsel_choose( &g_s ), 0 );
        CHECK_EQ( dmsel_persist_write( &g_s, 1, "old", 4 ), DMSEL_OK );
        g_f.fail_after = g_f.programs + cut;
        (void)dmsel_persist_write( &g_s, 1, "new!!", 6 );
        reset();
        {
            int n = dmsel_persist_read( &g_s, 1, buf, sizeof(buf) );
            CHECK( n == 4 || n == 6 );                          // the old one, or the new one - not a mix
            CHECK( (n == 4 && memcmp( buf, "old", 4 ) == 0) || (n == 6 && memcmp( buf, "new!!", 6 ) == 0) );
        }
        CHECK_EQ( dmsel_persist_write( &g_s, 2, "after", 6 ), DMSEL_OK );
        CHECK_EQ( dmsel_persist_read( &g_s, 2, buf, sizeof(buf) ), 6 );
        CHECK_EQ( dmsel_choose( &g_s ), 0 );
    }
}

static void test_power_cut_while_choosing( void )
{
    int cut;

    // The cut when the selector writes a try: the start must still happen from a good bank
    for( cut = 0; cut < 4; cut++ )
    {
        setup(); put_image( 0, 1, 0x4000, 1 ); put_image( 1, 2, 0x4000, 2 ); reset();
        CHECK_EQ( dmsel_choose( &g_s ), 1 );
        CHECK_EQ( dmsel_select( &g_s, 0, 1 ), DMSEL_OK );       // A on trial, B ran before
        g_f.fail_after = g_f.programs + cut;
        reset();
        g_f.fail_after = g_f.programs + cut;
        (void)dmsel_choose( &g_s );
        reset();
        {
            int bank = dmsel_choose( &g_s );
            CHECK( bank == 0 || bank == 1 );
        }
    }
}

static void test_get_info_extensible( void )
{
    dmsel_bank_info_t info;
    uint32_t small[2];

    setup(); put_image( 0, 3, 0x4000, 1 ); reset();
    CHECK_EQ( dmsel_choose( &g_s ), 0 );
    // A caller built with a smaller structure gets the part that fits and nothing beyond it
    small[0] = 8; small[1] = 0xDEADBEEF;
    CHECK_EQ( dmsel_get_info( &g_s, 0, (dmsel_bank_info_t*)small ), DMSEL_OK );
    CHECK_EQ( small[0], 8 );
    CHECK_EQ( small[1], DMSEL_BANK_VALID );
    info.struct_size = sizeof(info);
    CHECK_EQ( dmsel_get_info( &g_s, 5, &info ), DMSEL_ERR_PARAM );
    CHECK_EQ( dmsel_get_info( &g_s, 1, &info ), DMSEL_OK );
    CHECK_EQ( info.state, DMSEL_BANK_EMPTY );
    CHECK_EQ( info.version, 0 );
    CHECK_EQ( info.capacity, BANK_SIZE );
}

/** An image made by tools/dmsel_mkimage.py (the file is the argument) is a good image for the core */
static int check_tool_image( const char* path )
{
    FILE* f = fopen( path, "rb" );
    size_t n;

    setup(); reset();
    if( f == NULL )
    {
        printf( "cannot open %s\n", path );
        return 1;
    }
    n = fread( g_f.flash + BANK_A, 1, BANK_SIZE, f );
    fclose( f );
    CHECK( n > 512 );
    CHECK_EQ( dmsel_verify( &g_s, 0 ), DMSEL_OK );
    g_f.flash[BANK_A + n - 1] ^= 1;
    CHECK_EQ( dmsel_verify( &g_s, 0 ), DMSEL_ERR_BAD );
    printf( "image of the tool: %d checks, %d failures\n", g_checks, g_failures );
    return g_failures ? 1 : 0;
}

int main( int argc, char** argv )
{
    if( argc > 1 )
    {
        return check_tool_image( argv[1] );
    }
    RUN( test_crc );
    RUN( test_nothing_to_start );
    RUN( test_single_image_starts );
    RUN( test_newest_image_without_a_state );
    RUN( test_trial_confirmed );
    RUN( test_trial_not_confirmed_goes_back );
    RUN( test_watchdog_only_for_a_trial );
    RUN( test_permanent_select );
    RUN( test_damaged_image_falls_back );
    RUN( test_header_checks );
    RUN( test_lost_state_is_rebuilt );
    RUN( test_persistency );
    RUN( test_store_is_compacted );
    RUN( test_item_too_big );
    RUN( test_power_cut_while_writing );
    RUN( test_power_cut_while_choosing );
    RUN( test_get_info_extensible );
    printf( "test_selector: %d checks, %d failures\n", g_checks, g_failures );
    return g_failures ? 1 : 0;
}
