/**
 * @file flash.c
 * @brief The selector's port for the ESP32-S3: the flash as memory (the data cache and its MMU) and the ROM's SPI flash driver
 *
 * The selector is loaded into the RAM by the ROM, the flash is not in the memory of the chip yet: the MMU maps its 64 kB pages
 * into the window of the data bus (0x3C000000, 16 MB of the board's chip), the same sequence as the bootloader of ESP-IDF
 * (bootloader_reset_mmu, bootloader_mmap). Erasing and programming is the ROM's driver (esp_rom_spiflash_*); the cache is
 * suspended while the SPI works and what it holds is dropped afterwards.
 *
 * Only the store of the layout (user) is ever erased or programmed from here (a guard): a mistake of the core cannot touch
 * the selector or the banks.
 */
#include <stdint.h>
#include <string.h>
#include "dmsel.h"
#include "dmsel_platform.h"
#include "dmsel_mcu.h"

#define REG(a)                  (*(volatile uint32_t*)(a))
#define EXTMEM_DCACHE_CTRL1     0x600C4004u
#define EXTMEM_ICACHE_CTRL1     0x600C4064u
#define CACHE_SHUT_CORE0_BUS    (1u << 0)

#define FLASH_SIZE              0x1000000u      // the chip of the board: 16 MB
#define MMU_PAGE_SIZE           0x10000u
#define MMU_ACCESS_FLASH        0u
#define SECTOR_SIZE             0x1000u
#define PAGE_SIZE               0x100u

// The ROM (selector.ld of the mcu)
extern uint32_t rom_Cache_Suspend_DCache( void );
extern void     Cache_Resume_DCache( uint32_t autoload );
extern void     Cache_Invalidate_DCache_All( void );
extern void     Cache_MMU_Init( void );
extern int      Cache_Dbus_MMU_Set( uint32_t ext_ram, uint32_t vaddr, uint32_t paddr, uint32_t psize, uint32_t num, uint32_t fixed );
extern int      esp_rom_spiflash_unlock( void );
extern int      esp_rom_spiflash_config_param( uint32_t device_id, uint32_t chip_size, uint32_t block_size,
                                               uint32_t sector_size, uint32_t page_size, uint32_t status_mask );
extern int      esp_rom_spiflash_erase_sector( uint32_t sector_number );
extern int      esp_rom_spiflash_write( uint32_t dest_addr, const uint32_t* src, int32_t len );
/** Points to the ROM's data of the flash chip, whose first word is the id of the device */
extern const uint32_t* rom_spiflash_legacy_data;
extern uint32_t rom_Cache_Suspend_ICache( void );
extern void     Cache_Resume_ICache( uint32_t autoload );
extern int      g_dmsel_icache_on;              // image.c: the image of a bank runs from the flash through the instruction cache

/** The SPI cannot serve the caches while it works on the flash: they are suspended (the code here is in the RAM) */
static void caches_suspend( uint32_t autoload[2] )
{
    autoload[0] = rom_Cache_Suspend_DCache();
    autoload[1] = g_dmsel_icache_on ? rom_Cache_Suspend_ICache() : 0;
}

static void caches_resume( const uint32_t autoload[2] )
{
    Cache_Invalidate_DCache_All();
    Cache_Resume_DCache( autoload[0] );
    if( g_dmsel_icache_on )
    {
        Cache_Resume_ICache( autoload[1] );
    }
}

int dmsel_mcu_flash_init( void )
{
    uint32_t autoload = rom_Cache_Suspend_DCache();
    int result;

    Cache_Invalidate_DCache_All();
    Cache_MMU_Init();
    REG( EXTMEM_ICACHE_CTRL1 ) &= ~CACHE_SHUT_CORE0_BUS;
    REG( EXTMEM_DCACHE_CTRL1 ) &= ~CACHE_SHUT_CORE0_BUS;
    result = Cache_Dbus_MMU_Set( MMU_ACCESS_FLASH, DMSEL_MCU_FLASH_ADDRESS, 0, MMU_PAGE_SIZE / 1024, FLASH_SIZE / MMU_PAGE_SIZE, 0 );
    // The ROM's driver knows the size of the chip from the header of the image it booted (it has 2 MB until told otherwise)
    esp_rom_spiflash_config_param( rom_spiflash_legacy_data[0], FLASH_SIZE, MMU_PAGE_SIZE, SECTOR_SIZE, PAGE_SIZE, 0xFFFF );
    esp_rom_spiflash_unlock();
    Cache_Resume_DCache( autoload );
    return result == 0 ? 0 : -1;
}

static int allowed( void* user, uint32_t offset, uint32_t size )
{
    const dmsel_layout_t* l = (const dmsel_layout_t*)user;

    return offset >= l->store_offset && offset + size <= l->store_offset + l->store_size && offset + size >= offset;
}

int dmsel_mcu_erase( void* user, uint32_t offset, uint32_t size )
{
    uint32_t autoload[2], sector;
    int result = 0;

    if( (offset % SECTOR_SIZE) != 0 || (size % SECTOR_SIZE) != 0 || !allowed( user, offset, size ) )
    {
        return -1;
    }
    caches_suspend( autoload );
    for( sector = offset / SECTOR_SIZE; sector < (offset + size) / SECTOR_SIZE && result == 0; sector++ )
    {
        result = esp_rom_spiflash_erase_sector( sector ) == 0 ? 0 : -1;
    }
    caches_resume( autoload );
    return result;
}

int dmsel_mcu_program( void* user, uint32_t offset, const void* data, uint32_t size )
{
    const uint8_t* d = (const uint8_t*)data;
    uint32_t chunk[PAGE_SIZE / 4], autoload[2], i, n;
    int result = 0;

    if( (offset & 3u) != 0 || (size & 3u) != 0 || !allowed( user, offset, size ) )
    {
        return -1;
    }
    caches_suspend( autoload );
    for( i = 0; i < size && result == 0; i += n )
    {
        n = size - i < PAGE_SIZE ? size - i : PAGE_SIZE;
        memcpy( chunk, d + i, n );                  // the ROM wants the source aligned to a word
        result = esp_rom_spiflash_write( offset + i, chunk, (int32_t)n ) == 0 ? 0 : -1;
    }
    caches_resume( autoload );
    return result;
}
