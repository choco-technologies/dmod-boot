/**
 * @file dmsel.h
 * @brief The selector: the code of the first sector that picks the firmware bank to start, keeps the persistent data
 *
 * Portable C. Everything that depends on the chip is behind dmsel_port_t (read the flash, erase, program, jump); the
 * layout of the flash is a dmsel_layout_t. The selector owns one sector of the flash (the store): a log of records -
 * the state of the banks and the persistent items of Dmod_WritePersistency().
 */
#ifndef DMSEL_H
#define DMSEL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DMSEL_MAX_BANKS         4
#define DMSEL_HEADER_MAGIC      0x4B424D44u     //!< "DMBK"
#define DMSEL_HEADER_VERSION    1
#define DMSEL_HEADER_MAX_SIZE   512             //!< The header is at the start of a bank, the vectors follow at 512 (VTOR)

/** Results: 0, or negative */
typedef enum
{
    DMSEL_OK            =  0,
    DMSEL_ERR_PARAM     = -1,   //!< Wrong argument (no such bank, ...)
    DMSEL_ERR_NOENT     = -2,   //!< No such persistent item
    DMSEL_ERR_NOSPACE   = -3,   //!< The store is full
    DMSEL_ERR_IO        = -4,   //!< The flash failed
    DMSEL_ERR_EMPTY     = -5,   //!< The bank is empty
    DMSEL_ERR_BAD       = -6,   //!< The image in the bank is damaged
} dmsel_result_t;

/** State of a bank - the numbers are those of Dmod_FirmwareBankState_t */
typedef enum
{
    DMSEL_BANK_EMPTY        = 0,
    DMSEL_BANK_INVALID      = 1,
    DMSEL_BANK_VALID        = 2,
    DMSEL_BANK_TRIAL        = 3,
    DMSEL_BANK_CONFIRMED    = 4,
} dmsel_bank_state_t;

/**
 * Header of an image, in the first bytes of a bank (the tool that makes the image writes it after the linking).
 * The rest of the 512 bytes is 0xFF. The image is [bank start, bank start + image_size).
 */
typedef struct
{
    uint32_t    magic;          //!< DMSEL_HEADER_MAGIC
    uint16_t    header_version; //!< DMSEL_HEADER_VERSION
    uint16_t    header_size;    //!< Where the code starts (the vectors): at least sizeof(dmsel_header_t), at most 512
    uint32_t    image_size;     //!< Of the whole image, the header included
    uint32_t    version;        //!< The bigger the newer
    uint32_t    image_crc;      //!< CRC-32 of [header_size, image_size)
    uint32_t    entry_offset;   //!< Of the vector table from the start of the bank (a multiple of 512)
    uint32_t    flags;          //!< 0
    uint32_t    header_crc;     //!< CRC-32 of the bytes above
} dmsel_header_t;

/** What dmsel_get_info() tells (the layout is that of Dmod_FirmwareBankInfo_t) */
typedef struct
{
    uint32_t    struct_size;
    uint32_t    state;
    uint32_t    version;
    uint32_t    size;
    uint32_t    tries;
    uint32_t    reserved;
    uint64_t    address;
    uint64_t    capacity;
} dmsel_bank_info_t;

/** Where things are in the flash (offsets from the beginning of the flash) */
typedef struct
{
    uint32_t    offset;
    uint32_t    capacity;
} dmsel_bank_t;

typedef struct
{
    uint32_t        flash_address;      //!< Address of the offset 0 in the memory of the chip (0x08000000)
    uint32_t        store_offset;       //!< The sector of the selector's store
    uint32_t        store_size;
    uint32_t        bank_count;
    dmsel_bank_t    banks[DMSEL_MAX_BANKS];
    uint32_t        max_tries;          //!< Starts of an image on trial that does not confirm, before it is dropped
    uint32_t        watchdog_ms;        //!< Watchdog armed for an image on trial (0: none); the firmware has to feed it
} dmsel_layout_t;

/** The chip */
typedef struct
{
    const uint8_t*  flash;                                                      //!< The flash as memory: offset 0 first
    int           (*erase)( void* user, uint32_t offset, uint32_t size );       //!< Whole sectors; 0 or negative
    int           (*program)( void* user, uint32_t offset, const void* data, uint32_t size ); //!< Words, only on erased flash
    void          (*jump)( void* user, uint32_t vector_address );               //!< Does not return
    void          (*log)( void* user, const char* text );                       //!< May be NULL
    void          (*watchdog_start)( void* user, uint32_t timeout_ms );         //!< May be NULL; cannot be stopped
    void*           user;
} dmsel_port_t;

typedef struct
{
    const dmsel_layout_t*   layout;
    const dmsel_port_t*     port;
    uint8_t                 selected;       //!< Bank that is started (DMSEL_MAX_BANKS: none)
    uint8_t                 previous;       //!< Bank to go back to when the one on trial does not confirm (DMSEL_MAX_BANKS: none)
    uint8_t                 running;        //!< Bank that was started (DMSEL_MAX_BANKS: none)
    uint8_t                 state_valid;    //!< A state record was found in the store
    uint8_t                 state[DMSEL_MAX_BANKS];
    uint8_t                 tries[DMSEL_MAX_BANKS];
    uint32_t                store_end;      //!< Offset in the store of the first free byte
    uint8_t*                scratch;        //!< layout->store_size bytes of RAM (the compaction of the store, the records)
} dmsel_t;

uint32_t dmsel_crc32( uint32_t crc, const void* data, size_t size );

/**
 * Reads the state from the store (a lost state is rebuilt from the banks at the next dmsel_choose).
 * @param scratch  layout->store_size bytes that are used while a call writes to the store, and only then
 */
int dmsel_init( dmsel_t* s, const dmsel_layout_t* layout, const dmsel_port_t* port, uint8_t* scratch );

/**
 * Decides which bank to start, stores what has to be remembered (a try of an image on trial) and returns the bank.
 * @return bank number, or a negative result when there is nothing to start
 */
int dmsel_choose( dmsel_t* s );

/** dmsel_choose() and the jump into the image; when nothing can be started it logs and returns */
void dmsel_boot( dmsel_t* s );

// --- What the running firmware asks for (Dmod_Firmware*, Dmod_*Persistency)
int dmsel_bank_count( const dmsel_t* s );
int dmsel_running_bank( const dmsel_t* s );
int dmsel_get_info( dmsel_t* s, int bank, dmsel_bank_info_t* info );
int dmsel_verify( dmsel_t* s, int bank );
int dmsel_select( dmsel_t* s, int bank, int trial );
int dmsel_ready( dmsel_t* s );
int dmsel_persist_write( dmsel_t* s, uint32_t id, const void* data, size_t size );
int dmsel_persist_read( dmsel_t* s, uint32_t id, void* buffer, size_t buffer_size );

#ifdef __cplusplus
}
#endif

#endif /* DMSEL_H */
