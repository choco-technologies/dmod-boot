/**
 * @brief The firmware interface of the SAL (Dmod_Firmware*, Dmod_*Persistency) over the table of the selector.
 *
 * The image that is linked for a bank (DMBOOT_BANK) is started by the selector, which leaves a table of functions in
 * its sector (selector/include/dmsel_table.h). The state of the banks is read from the store of the selector at the
 * first call; the memory for it is ours (the RAM of the selector is gone), and so is the scratch that the calls
 * writing to the store need - taken from the heap for the time of the call only.
 */
#include "dmod.h"
#include "dmsel_table.h"
#include <errno.h>
#include <string.h>

#ifndef DMBOOT_BANK_INDEX
#   error "DMBOOT_BANK_INDEX (the number of the bank that the image is linked for) is required"
#endif

static dmsel_t g_state;
static uint8_t g_dummy_scratch;
static bool g_initialized;
static const dmsel_table_t* g_table;

static int to_errno(int result)
{
    switch(result)
    {
        case DMSEL_ERR_PARAM:   return -EINVAL;
        case DMSEL_ERR_NOENT:   return -ENOENT;
        case DMSEL_ERR_NOSPACE: return -ENOSPC;
        case DMSEL_ERR_IO:      return -EIO;
        case DMSEL_ERR_EMPTY:   return -ENODATA;
        case DMSEL_ERR_BAD:     return -EBADMSG;
        default:                return result < 0 ? -EIO : result;
    }
}

/* The table of the selector, with the state read; NULL when there is no selector (the image was not started by it) */
static const dmsel_table_t* get_table(void)
{
    if(g_initialized)
    {
        return g_table;
    }
    g_initialized = true;

    const dmsel_table_t* table = (const dmsel_table_t*)DMSEL_TABLE_ADDRESS;
    if(table->magic != DMSEL_TABLE_MAGIC || table->abi != DMSEL_TABLE_ABI || table->state_size != sizeof(dmsel_t))
    {
        return NULL;
    }
    /* The scratch is given for the calls that write; the state only reads at init */
    if(table->init(&g_state, DMBOOT_BANK_INDEX, &g_dummy_scratch) != 0)
    {
        return NULL;
    }
    g_table = table;
    return g_table;
}

/* Runs a call that writes to the store: it needs the scratch (the size of the store) for its time */
#define WITH_SCRATCH(call)                                          \
    do {                                                            \
        uint8_t* scratch = Dmod_Malloc(table->scratch_size);        \
        if(scratch == NULL)                                         \
        {                                                           \
            return -ENOMEM;                                         \
        }                                                           \
        g_state.scratch = scratch;                                  \
        result = (call);                                            \
        g_state.scratch = &g_dummy_scratch;                         \
        Dmod_Free(scratch);                                         \
    } while(0)

int Dmod_FirmwareReady(void)
{
    const dmsel_table_t* table = get_table();
    int result;
    if(table == NULL)
    {
        return -ENOSYS;
    }
    WITH_SCRATCH(table->ready(&g_state));
    return to_errno(result);
}

int Dmod_FirmwareGetBankCount(void)
{
    const dmsel_table_t* table = get_table();
    return table != NULL ? table->bank_count(&g_state) : -ENOSYS;
}

int Dmod_FirmwareGetRunningBank(void)
{
    const dmsel_table_t* table = get_table();
    if(table == NULL)
    {
        return -ENOSYS;
    }
    int bank = table->running_bank(&g_state);
    return bank >= 0 ? bank : DMOD_FIRMWARE_BANK_NONE;
}

int Dmod_FirmwareGetBankInfo(int Bank, Dmod_FirmwareBankInfo_t* Info)
{
    const dmsel_table_t* table = get_table();
    if(table == NULL)
    {
        return -ENOSYS;
    }
    if(Info == NULL)
    {
        return -EINVAL;
    }
    dmsel_bank_info_t info;
    int result = table->get_info(&g_state, Bank, &info);
    if(result != 0)
    {
        return to_errno(result);
    }
    /* The layouts are the same, the caller's StructSize is what it is */
    uint32_t size = Info->StructSize < sizeof(info) ? Info->StructSize : (uint32_t)sizeof(info);
    uint32_t struct_size = Info->StructSize;
    memcpy(Info, &info, size);
    Info->StructSize = struct_size;
    return 0;
}

int Dmod_FirmwareVerifyBank(int Bank)
{
    const dmsel_table_t* table = get_table();
    int result;
    if(table == NULL)
    {
        return -ENOSYS;
    }
    WITH_SCRATCH(table->verify(&g_state, Bank));
    return to_errno(result);
}

int Dmod_FirmwareSelectBank(int Bank, bool Trial)
{
    const dmsel_table_t* table = get_table();
    int result;
    if(table == NULL)
    {
        return -ENOSYS;
    }
    WITH_SCRATCH(table->select(&g_state, Bank, Trial ? 1 : 0));
    return to_errno(result);
}

int Dmod_WritePersistency(uint32_t Id, const void* Data, size_t Size)
{
    const dmsel_table_t* table = get_table();
    int result;
    if(table == NULL)
    {
        return -ENOSYS;
    }
    WITH_SCRATCH(table->persist_write(&g_state, Id, Data, Size));
    return to_errno(result);
}

int Dmod_ReadPersistency(uint32_t Id, void* Buffer, size_t BufferSize)
{
    const dmsel_table_t* table = get_table();
    if(table == NULL)
    {
        return -ENOSYS;
    }
    return to_errno(table->persist_read(&g_state, Id, Buffer, BufferSize));
}
