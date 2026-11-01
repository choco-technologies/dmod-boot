/**
 * @file dmsel_table.h
 * @brief The table of functions that the selector leaves in its sector for the firmware
 *
 * The firmware cannot link to the selector, it finds the table at a fixed address (DMSEL_TABLE_ADDRESS) and calls the
 * functions through it. The state (dmsel_t) is the firmware's own memory: the RAM of the selector is gone when the
 * firmware starts. The functions that write the store need dmsel_table_t.scratch_size bytes of RAM, given at init.
 *
 * What the firmware reads at its start, before it uses the RAM of the selector (the first 64 kB of the DTCM): log_address.
 */
#ifndef DMSEL_TABLE_H
#define DMSEL_TABLE_H

#include "dmsel.h"

#ifdef __cplusplus
extern "C" {
#endif

#define DMSEL_TABLE_ADDRESS     0x08000100u
#define DMSEL_TABLE_MAGIC       0x4C455344u     //!< "DSEL"
#define DMSEL_TABLE_ABI         1

typedef struct
{
    uint32_t    magic;              //!< DMSEL_TABLE_MAGIC
    uint32_t    abi;                //!< DMSEL_TABLE_ABI; a firmware built for another does not use the table
    uint32_t    table_size;         //!< sizeof of this structure in the selector
    uint32_t    state_size;         //!< sizeof(dmsel_t): the memory that the firmware gives to init
    uint32_t    scratch_size;       //!< Of the RAM that init takes
    uint32_t    version;            //!< Of the selector (a number)
    uint32_t    log_address;        //!< The log of the selector (a dmlog buffer in the DTCM), valid until the firmware uses that RAM
    uint32_t    log_size;
    /** @param running  the bank that the firmware was linked for, i.e. runs from */
    int       (*init)( dmsel_t* s, int running, uint8_t* scratch );
    int       (*bank_count)( const dmsel_t* s );
    int       (*running_bank)( const dmsel_t* s );
    int       (*get_info)( dmsel_t* s, int bank, dmsel_bank_info_t* info );
    int       (*verify)( dmsel_t* s, int bank );
    int       (*select)( dmsel_t* s, int bank, int trial );
    int       (*ready)( dmsel_t* s );
    int       (*persist_write)( dmsel_t* s, uint32_t id, const void* data, size_t size );
    int       (*persist_read)( dmsel_t* s, uint32_t id, void* buffer, size_t buffer_size );
} dmsel_table_t;

#ifdef __cplusplus
}
#endif

#endif /* DMSEL_TABLE_H */
