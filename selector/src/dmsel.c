/**
 * @file dmsel.c
 * @brief The selector - choice of the bank, the store of the state and of the persistent items
 *
 * The store is one sector of the flash used as a log: records are appended, a record is valid when its CRC is, the latest
 * valid record of a kind wins. A full store is compacted in RAM (the sector is erased and written again: a power cut in
 * that moment loses the persistent items, and the state is rebuilt from the banks: the newest good image).
 */
#include <string.h>
#include "dmsel.h"

#define NO_BANK         DMSEL_MAX_BANKS
#define REC_HDR         8u
enum { REC_STATE = 1, REC_PERSIST = 2, REC_DELETE = 3 };
#define STATE_SIZE      (2u + 2u + DMSEL_MAX_BANKS + DMSEL_MAX_BANKS)

typedef struct
{
    uint16_t    type;
    uint16_t    len;        //!< Of the payload, without the padding
    uint32_t    crc;        //!< Of type, len and the payload
} rec_t;

// ---------------------------------------------------------------------------------------------------------------------
//      Helpers
// ---------------------------------------------------------------------------------------------------------------------

uint32_t dmsel_crc32( uint32_t crc, const void* data, size_t size )
{
    static const uint32_t table[16] =
    {
        0x00000000, 0x1DB71064, 0x3B6E20C8, 0x26D930AC, 0x76DC4190, 0x6B6B51F4, 0x4DB26158, 0x5005713C,
        0xEDB88320, 0xF00F9344, 0xD6D6A3E8, 0xCB61B38C, 0x9B64C2B0, 0x86D3D2D4, 0xA00AE278, 0xBDBDF21C
    };
    const uint8_t* p = (const uint8_t*)data;

    crc = ~crc;
    while( size-- > 0 )
    {
        crc ^= *p++;
        crc = (crc >> 4) ^ table[crc & 15u];
        crc = (crc >> 4) ^ table[crc & 15u];
    }
    return ~crc;
}

static uint32_t pad4( uint32_t n )
{
    return (n + 3u) & ~3u;
}

static void say( const dmsel_t* s, const char* text, int value, int with_value )
{
    char buf[64];
    size_t n = 0, i;
    char digits[12];
    unsigned v;
    int d = 0;

    if( s->port->log == NULL )
    {
        return;
    }
    for( i = 0; text[i] != '\0' && n < 40; i++ )
    {
        buf[n++] = text[i];
    }
    if( with_value )
    {
        if( value < 0 )
        {
            buf[n++] = '-';
            v = (unsigned)(-value);
        }
        else
        {
            v = (unsigned)value;
        }
        do
        {
            digits[d++] = (char)('0' + v % 10u);
            v /= 10u;
        }
        while( v != 0 );
        while( d > 0 )
        {
            buf[n++] = digits[--d];
        }
    }
    buf[n++] = '\n';
    buf[n] = '\0';
    s->port->log( s->port->user, buf );
}

static int is_blank( const uint8_t* p, uint32_t n )
{
    while( n-- > 0 )
    {
        if( *p++ != 0xFF )
        {
            return 0;
        }
    }
    return 1;
}

static const uint8_t* store_base( const dmsel_t* s )
{
    return s->port->flash + s->layout->store_offset;
}

// ---------------------------------------------------------------------------------------------------------------------
//      The store
// ---------------------------------------------------------------------------------------------------------------------

/** 1: a valid record, 0: the end (blank), -1: garbage (a record that was not finished) - both end the log */
static int rec_read( const dmsel_t* s, uint32_t off, rec_t* r, const uint8_t** payload )
{
    const uint8_t* p = store_base( s ) + off;
    uint32_t crc;

    if( off + REC_HDR > s->layout->store_size )
    {
        return 0;
    }
    memcpy( r, p, REC_HDR );
    if( r->type == 0xFFFF && r->len == 0xFFFF && r->crc == 0xFFFFFFFFu )
    {
        return 0;
    }
    if( off + REC_HDR + pad4( r->len ) > s->layout->store_size )
    {
        return -1;
    }
    crc = dmsel_crc32( 0, p, 4 );
    crc = dmsel_crc32( crc, p + REC_HDR, r->len );
    if( crc != r->crc )
    {
        return -1;
    }
    *payload = p + REC_HDR;
    return 1;
}

static uint32_t le32( const uint8_t* p )
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/** Is there a record after @p from_off that sets or deletes the item @p id? */
static int later_item( const dmsel_t* s, uint32_t from_off, uint32_t id )
{
    rec_t r;
    const uint8_t* payload;
    uint32_t off = from_off;

    while( rec_read( s, off, &r, &payload ) == 1 )
    {
        if( (r.type == REC_PERSIST || r.type == REC_DELETE) && r.len >= 4 && le32( payload ) == id )
        {
            return 1;
        }
        off += REC_HDR + pad4( r.len );
    }
    return 0;
}

/** Reads the log: the latest state, the end of the log */
static void load_state( dmsel_t* s )
{
    rec_t r;
    const uint8_t* payload;
    uint32_t off = 0;
    unsigned i;

    s->state_valid = 0;
    while( rec_read( s, off, &r, &payload ) == 1 )
    {
        if( r.type == REC_STATE && r.len == STATE_SIZE )
        {
            s->selected = payload[0];
            s->previous = payload[1];
            for( i = 0; i < DMSEL_MAX_BANKS; i++ )
            {
                s->state[i] = payload[4 + i];
                s->tries[i] = payload[4 + DMSEL_MAX_BANKS + i];
            }
            s->state_valid = 1;
        }
        off += REC_HDR + pad4( r.len );
    }
    s->store_end = off;
}

static int write_record( dmsel_t* s, uint32_t off, uint16_t type, const void* a, uint32_t na, const void* b, uint32_t nb )
{
    uint8_t* buf = s->scratch;
    uint32_t len = na + nb, padded = pad4( len );
    rec_t r;

    memset( buf, 0xFF, padded );
    if( na ) memcpy( buf, a, na );
    if( nb ) memcpy( buf + na, b, nb );
    r.type = type;
    r.len = (uint16_t)len;
    r.crc = dmsel_crc32( 0, &r, 4 );
    r.crc = dmsel_crc32( r.crc, buf, len );
    // The payload first, the header last: a record is there only when its header is
    if( padded != 0 && s->port->program( s->port->user, s->layout->store_offset + off + REC_HDR, buf, padded ) != 0 )
    {
        return DMSEL_ERR_IO;
    }
    return s->port->program( s->port->user, s->layout->store_offset + off, &r, REC_HDR ) == 0 ? DMSEL_OK : DMSEL_ERR_IO;
}

static void state_payload( const dmsel_t* s, uint8_t* out )
{
    unsigned i;
    out[0] = s->selected;
    out[1] = s->previous;
    out[2] = 0;
    out[3] = 0;
    for( i = 0; i < DMSEL_MAX_BANKS; i++ )
    {
        out[4 + i] = s->state[i];
        out[4 + DMSEL_MAX_BANKS + i] = s->tries[i];
    }
}

/** Erases the store and writes the state and the latest value of every item again */
static int compact( dmsel_t* s )
{
    uint8_t* out = s->scratch;
    uint8_t payload[STATE_SIZE];
    rec_t r, hdr;
    const uint8_t* p;
    uint32_t o = 0, off = 0;

    state_payload( s, payload );
    hdr.type = REC_STATE;
    hdr.len = STATE_SIZE;
    hdr.crc = dmsel_crc32( dmsel_crc32( 0, &hdr, 4 ), payload, STATE_SIZE );
    memcpy( out, &hdr, REC_HDR );
    memcpy( out + REC_HDR, payload, STATE_SIZE );
    o = REC_HDR + pad4( STATE_SIZE );

    while( rec_read( s, off, &r, &p ) == 1 )
    {
        uint32_t total = REC_HDR + pad4( r.len );
        if( r.type == REC_PERSIST && r.len >= 4 && !later_item( s, off + total, le32( p ) ) )
        {
            memcpy( out + o, store_base( s ) + off, total );
            o += total;
        }
        off += total;
    }

    say( s, "dmsel: store compacted", 0, 0 );
    if( s->port->erase( s->port->user, s->layout->store_offset, s->layout->store_size ) != 0 ||
        s->port->program( s->port->user, s->layout->store_offset, out, o ) != 0 )
    {
        return DMSEL_ERR_IO;
    }
    s->store_end = o;
    return DMSEL_OK;
}

static int append( dmsel_t* s, uint16_t type, const void* a, uint32_t na, const void* b, uint32_t nb )
{
    uint32_t total = REC_HDR + pad4( na + nb );
    int attempt;

    if( total > s->layout->store_size )
    {
        return DMSEL_ERR_NOSPACE;
    }
    for( attempt = 0; attempt < 2; attempt++ )
    {
        if( s->store_end + total <= s->layout->store_size &&
            is_blank( store_base( s ) + s->store_end, total ) )
        {
            int r = write_record( s, s->store_end, type, a, na, b, nb );
            if( r == DMSEL_OK )
            {
                s->store_end += total;
            }
            return r;
        }
        if( attempt == 0 )
        {
            int r = compact( s );
            if( r != DMSEL_OK )
            {
                return r;
            }
        }
    }
    return DMSEL_ERR_NOSPACE;
}

static int save_state( dmsel_t* s )
{
    uint8_t payload[STATE_SIZE];

    state_payload( s, payload );
    s->state_valid = 1;
    return append( s, REC_STATE, payload, STATE_SIZE, NULL, 0 );
}

// ---------------------------------------------------------------------------------------------------------------------
//      Images
// ---------------------------------------------------------------------------------------------------------------------

/** 0: a good image; DMSEL_ERR_EMPTY: nothing there; DMSEL_ERR_BAD: damaged */
static int check_image( const dmsel_t* s, unsigned bank, dmsel_header_t* out )
{
    const dmsel_bank_t* b = &s->layout->banks[bank];
    const uint8_t* p = s->port->flash + b->offset;
    dmsel_header_t h;

    memcpy( &h, p, sizeof(h) );
    if( h.magic != DMSEL_HEADER_MAGIC )
    {
        return is_blank( p, 16 ) ? DMSEL_ERR_EMPTY : DMSEL_ERR_BAD;
    }
    if( dmsel_crc32( 0, &h, sizeof(h) - 4 ) != h.header_crc || h.header_version != DMSEL_HEADER_VERSION ||
        h.header_size < sizeof(h) || h.header_size > DMSEL_HEADER_MAX_SIZE || h.image_size <= h.header_size ||
        h.image_size > b->capacity || h.entry_offset % 512u != 0 || h.entry_offset >= h.image_size )
    {
        return DMSEL_ERR_BAD;
    }
    if( dmsel_crc32( 0, p + h.header_size, h.image_size - h.header_size ) != h.image_crc )
    {
        return DMSEL_ERR_BAD;
    }
    if( out != NULL )
    {
        *out = h;
    }
    return DMSEL_OK;
}

/** The state is lost: the banks tell what there is - the newest good image is started */
static void rebuild( dmsel_t* s )
{
    unsigned i;
    uint32_t best_version = 0;
    int best = -1;

    for( i = 0; i < DMSEL_MAX_BANKS; i++ )
    {
        s->state[i] = DMSEL_BANK_EMPTY;
        s->tries[i] = 0;
    }
    for( i = 0; i < s->layout->bank_count; i++ )
    {
        dmsel_header_t h;
        int r = check_image( s, i, &h );
        if( r == DMSEL_OK )
        {
            s->state[i] = DMSEL_BANK_VALID;
            if( best < 0 || h.version > best_version )
            {
                best = (int)i;
                best_version = h.version;
            }
        }
        else
        {
            s->state[i] = r == DMSEL_ERR_EMPTY ? DMSEL_BANK_EMPTY : DMSEL_BANK_INVALID;
        }
    }
    s->selected = best < 0 ? NO_BANK : (uint8_t)best;
    s->previous = NO_BANK;
    say( s, "dmsel: state rebuilt from the banks, newest: ", best, 1 );
}

// ---------------------------------------------------------------------------------------------------------------------
//      Public
// ---------------------------------------------------------------------------------------------------------------------

int dmsel_init( dmsel_t* s, const dmsel_layout_t* layout, const dmsel_port_t* port, uint8_t* scratch )
{
    unsigned i;

    if( s == NULL || layout == NULL || port == NULL || layout->bank_count > DMSEL_MAX_BANKS || scratch == NULL )
    {
        return DMSEL_ERR_PARAM;
    }
    memset( s, 0, sizeof(*s) );
    s->layout = layout;
    s->port = port;
    s->scratch = scratch;
    s->selected = s->previous = s->running = NO_BANK;
    for( i = 0; i < DMSEL_MAX_BANKS; i++ )
    {
        s->state[i] = DMSEL_BANK_EMPTY;
    }
    load_state( s );
    return DMSEL_OK;
}

int dmsel_choose( dmsel_t* s )
{
    int pass;

    for( pass = 0; pass < 2; pass++ )
    {
        unsigned order[2 + DMSEL_MAX_BANKS], n = 0, k, i;

        if( pass == 1 || !s->state_valid )
        {
            rebuild( s );
        }
        order[n++] = s->selected;
        order[n++] = s->previous;
        for( i = 0; i < s->layout->bank_count; i++ )
        {
            order[n++] = i;
        }
        for( k = 0; k < n; k++ )
        {
            unsigned c = order[k], j, seen = 0;
            dmsel_header_t h;
            int r;

            if( c >= s->layout->bank_count )
            {
                continue;
            }
            for( j = 0; j < k; j++ )
            {
                seen |= (order[j] == c);
            }
            if( seen || s->state[c] == DMSEL_BANK_EMPTY || s->state[c] == DMSEL_BANK_INVALID )
            {
                continue;
            }
            r = check_image( s, c, &h );
            if( r != DMSEL_OK )
            {
                say( s, "dmsel: image damaged or missing in bank ", (int)c, 1 );
                s->state[c] = r == DMSEL_ERR_EMPTY ? DMSEL_BANK_EMPTY : DMSEL_BANK_INVALID;
                save_state( s );
                continue;
            }
            if( s->state[c] == DMSEL_BANK_TRIAL )
            {
                if( s->tries[c] >= s->layout->max_tries )
                {
                    say( s, "dmsel: bank did not confirm, dropped: ", (int)c, 1 );
                    s->state[c] = DMSEL_BANK_INVALID;
                    save_state( s );
                    continue;
                }
                s->tries[c]++;
                say( s, "dmsel: trial start, try ", s->tries[c], 1 );
            }
            else
            {
                s->previous = NO_BANK;
            }
            s->selected = s->running = (uint8_t)c;
            save_state( s );
            say( s, "dmsel: bank ", (int)c, 1 );
            return (int)c;
        }
    }
    say( s, "dmsel: nothing to start", 0, 0 );
    return DMSEL_ERR_EMPTY;
}

void dmsel_boot( dmsel_t* s )
{
    dmsel_header_t h;
    int bank = dmsel_choose( s );

    if( bank >= 0 && check_image( s, (unsigned)bank, &h ) == DMSEL_OK )
    {
        if( s->state[bank] == DMSEL_BANK_TRIAL && s->layout->watchdog_ms != 0 && s->port->watchdog_start != NULL )
        {
            // An image that hangs before it confirms is reset by the watchdog, and the next start counts a try
            s->port->watchdog_start( s->port->user, s->layout->watchdog_ms );
        }
        s->port->jump( s->port->user,
                       s->layout->flash_address + s->layout->banks[bank].offset + h.entry_offset );
    }
}

int dmsel_bank_count( const dmsel_t* s )
{
    return (int)s->layout->bank_count;
}

int dmsel_running_bank( const dmsel_t* s )
{
    return s->running < s->layout->bank_count ? (int)s->running : -1;
}

int dmsel_get_info( dmsel_t* s, int bank, dmsel_bank_info_t* info )
{
    dmsel_bank_info_t full;
    dmsel_header_t h;

    if( bank < 0 || (unsigned)bank >= s->layout->bank_count || info == NULL || info->struct_size == 0 )
    {
        return DMSEL_ERR_PARAM;
    }
    memset( &full, 0, sizeof(full) );
    full.struct_size = sizeof(full);
    full.state = s->state[bank];
    full.tries = s->tries[bank];
    full.address = (uint64_t)s->layout->flash_address + s->layout->banks[bank].offset;
    full.capacity = s->layout->banks[bank].capacity;
    memcpy( &h, s->port->flash + s->layout->banks[bank].offset, sizeof(h) );
    if( s->state[bank] != DMSEL_BANK_EMPTY && h.magic == DMSEL_HEADER_MAGIC )
    {
        full.version = h.version;
        full.size = h.image_size;
    }
    {
        uint32_t wanted = info->struct_size;        // The caller's, not ours
        memcpy( info, &full, wanted < sizeof(full) ? wanted : sizeof(full) );
        info->struct_size = wanted;
    }
    return DMSEL_OK;
}

int dmsel_verify( dmsel_t* s, int bank )
{
    int r;
    uint8_t wanted;

    if( bank < 0 || (unsigned)bank >= s->layout->bank_count )
    {
        return DMSEL_ERR_PARAM;
    }
    r = check_image( s, (unsigned)bank, NULL );
    if( r == DMSEL_OK )
    {
        wanted = (s->state[bank] == DMSEL_BANK_EMPTY || s->state[bank] == DMSEL_BANK_INVALID) ? DMSEL_BANK_VALID : s->state[bank];
    }
    else
    {
        wanted = r == DMSEL_ERR_EMPTY ? DMSEL_BANK_EMPTY : DMSEL_BANK_INVALID;
    }
    if( wanted != s->state[bank] )
    {
        s->state[bank] = wanted;
        s->tries[bank] = 0;
        if( save_state( s ) != DMSEL_OK )
        {
            return DMSEL_ERR_IO;
        }
    }
    return r;
}

int dmsel_select( dmsel_t* s, int bank, int trial )
{
    int r = dmsel_verify( s, bank );

    if( r != DMSEL_OK )
    {
        return r;
    }
    if( trial )
    {
        // Back to the bank that runs now - or to the one that was to be started, when this is run from nowhere
        uint8_t back = s->running < s->layout->bank_count ? s->running : s->selected;
        if( back == (uint8_t)bank || back >= s->layout->bank_count )
        {
            back = NO_BANK;
        }
        else if( s->state[back] == DMSEL_BANK_TRIAL )
        {
            back = s->previous;     // The running one is not confirmed itself: the one before it
        }
        s->previous = back;
        s->state[bank] = DMSEL_BANK_TRIAL;
    }
    else
    {
        s->previous = NO_BANK;
        s->state[bank] = DMSEL_BANK_CONFIRMED;
    }
    s->tries[bank] = 0;
    s->selected = (uint8_t)bank;
    return save_state( s );
}

int dmsel_ready( dmsel_t* s )
{
    if( s->running >= s->layout->bank_count )
    {
        return DMSEL_ERR_PARAM;
    }
    if( s->state[s->running] != DMSEL_BANK_TRIAL )
    {
        return DMSEL_OK;
    }
    s->state[s->running] = DMSEL_BANK_CONFIRMED;
    s->tries[s->running] = 0;
    s->previous = NO_BANK;
    return save_state( s );
}

int dmsel_persist_read( dmsel_t* s, uint32_t id, void* buffer, size_t buffer_size )
{
    rec_t r;
    const uint8_t* p;
    const uint8_t* found = NULL;
    uint32_t found_len = 0, off = 0;

    if( buffer == NULL && buffer_size != 0 )
    {
        return DMSEL_ERR_PARAM;
    }
    while( rec_read( s, off, &r, &p ) == 1 )
    {
        if( (r.type == REC_PERSIST || r.type == REC_DELETE) && r.len >= 4 && le32( p ) == id )
        {
            found = r.type == REC_PERSIST ? p + 4 : NULL;
            found_len = r.len - 4;
        }
        off += REC_HDR + pad4( r.len );
    }
    if( found == NULL )
    {
        return DMSEL_ERR_NOENT;
    }
    if( buffer_size != 0 )
    {
        memcpy( buffer, found, found_len < buffer_size ? found_len : buffer_size );
    }
    return (int)found_len;
}

int dmsel_persist_write( dmsel_t* s, uint32_t id, const void* data, size_t size )
{
    uint8_t idle[4];
    int current;

    if( (data == NULL && size != 0) || size > 0xFFF0u )
    {
        return DMSEL_ERR_PARAM;
    }
    idle[0] = (uint8_t)id;
    idle[1] = (uint8_t)(id >> 8);
    idle[2] = (uint8_t)(id >> 16);
    idle[3] = (uint8_t)(id >> 24);
    current = dmsel_persist_read( s, id, NULL, 0 );

    if( data == NULL )
    {
        return current < 0 ? DMSEL_OK : append( s, REC_DELETE, idle, 4, NULL, 0 );
    }
    if( current == (int)size && size > 0 )
    {
        // Already there: nothing to wear the flash for
        const uint8_t* p;
        rec_t r;
        uint32_t off = 0;
        const uint8_t* value = NULL;

        while( rec_read( s, off, &r, &p ) == 1 )
        {
            if( (r.type == REC_PERSIST || r.type == REC_DELETE) && r.len >= 4 && le32( p ) == id )
            {
                value = r.type == REC_PERSIST ? p + 4 : NULL;
            }
            off += REC_HDR + pad4( r.len );
        }
        if( value != NULL && memcmp( value, data, size ) == 0 )
        {
            return DMSEL_OK;
        }
    }
    return append( s, REC_PERSIST, idle, 4, data, (uint32_t)size );
}
