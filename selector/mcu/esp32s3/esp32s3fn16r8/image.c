/**
 * @file image.c
 * @brief ESP32-S3: what the selector does before it jumps into a bank - the pages of the bank into the window of the image,
 *        the instruction cache on
 *
 * The firmware is XIP: its code is read from the flash through the instruction cache, so the cache and the MMU have to be
 * ready when its first instruction is fetched. The pages of the bank are mapped to DMSEL_MCU_IMAGE_CODE (and so, the same
 * entries of the MMU, to DMSEL_MCU_IMAGE_DATA for the data bus), whichever the bank is: one build of the firmware starts from
 * both. The mapping of the flash the selector uses itself (entries 0..255) stays.
 */
#include <stdint.h>
#include "dmsel.h"
#include "dmsel_platform.h"
#include "dmsel_mcu.h"

#define MMU_PAGE_SIZE           0x10000u
#define MMU_ACCESS_FLASH        0u
#define ICACHE_SIZE             0x4000u         // 16 kB, 8 ways, 32 byte lines: what ESP-IDF configures
#define ICACHE_WAYS             8
#define ICACHE_LINE_SIZE        32

extern uint32_t rom_Cache_Suspend_DCache( void );
extern void     Cache_Resume_DCache( uint32_t autoload );
extern void     Cache_Invalidate_DCache_All( void );
extern int      Cache_Ibus_MMU_Set( uint32_t ext_ram, uint32_t vaddr, uint32_t paddr, uint32_t psize, uint32_t num, uint32_t fixed );
extern void     rom_config_instruction_cache_mode( uint32_t size, uint8_t ways, uint8_t line_size );
extern void     Cache_Invalidate_ICache_All( void );
extern void     Cache_Enable_ICache( uint32_t autoload );

int g_dmsel_icache_on;                          //!< The flash operations (flash.c) suspend the instruction cache as well

uint32_t dmsel_mcu_prepare_jump( void* user, uint32_t address )
{
    const dmsel_layout_t* l = (const dmsel_layout_t*)user;
    uint32_t bank, autoload;

    for( bank = 0; bank < l->bank_count; bank++ )
    {
        uint32_t start = l->flash_address + l->banks[bank].offset;

        if( address >= start && address - start < l->banks[bank].capacity )
        {
            uint32_t pages = (l->banks[bank].capacity + MMU_PAGE_SIZE - 1) / MMU_PAGE_SIZE;

            autoload = rom_Cache_Suspend_DCache();
            Cache_Invalidate_DCache_All();
            if( Cache_Ibus_MMU_Set( MMU_ACCESS_FLASH, DMSEL_MCU_IMAGE_CODE, l->banks[bank].offset, MMU_PAGE_SIZE / 1024, pages, 0 ) != 0 )
            {
                Cache_Resume_DCache( autoload );
                return 0;
            }
            Cache_Resume_DCache( autoload );
            rom_config_instruction_cache_mode( ICACHE_SIZE, ICACHE_WAYS, ICACHE_LINE_SIZE );
            Cache_Invalidate_ICache_All();
            Cache_Enable_ICache( 0 );
            g_dmsel_icache_on = 1;
            return DMSEL_MCU_IMAGE_CODE + (address - start);
        }
    }
    return 0;
}
