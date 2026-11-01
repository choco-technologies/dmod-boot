/* The selector (selector/) on the ESP32-S3: the ROM loads it from the flash (it is the second stage bootloader) into the RAM,
   where it runs - the code through the instruction bus (IRAM), the data through the data bus (DRAM): the same memory, the
   buses are 0x6f0000 apart.
   The place is the one of the ESP-IDF bootloader (components/bootloader/subproject/main/ld/esp32s3/bootloader.ld): the top of
   the RAM, below the buffers of the ROM (0x3fce9700), so that an application loaded into the low RAM does not overwrite it.
     DRAM 0x3fcd9700 .. 0x3fce9700   the table, the data, the bss and the stack (64 kB)
     IRAM 0x403c1700 .. 0x403c9700   the code (32 kB; the data bus sees it at 0x3fcd1700, just below the DRAM) */
MEMORY
{
    IRAM (rx)   : ORIGIN = 0x403c1700, LENGTH = 0x8000
    DRAM (rw)   : ORIGIN = 0x3fcd9700, LENGTH = 0x10000
}

/* Functions of the ROM that the selector calls (components/esp_rom/esp32s3/ld/esp32s3.rom.ld of ESP-IDF); the ROM is
   the same on every chip, the addresses are fixed. rom_spiflash_legacy_data is a pointer to the ROM's data of the flash chip */
ets_delay_us                        = 0x40000600;
esp_rom_spiflash_unlock             = 0x40000a2c;
esp_rom_spiflash_erase_sector       = 0x400009fc;
esp_rom_spiflash_write              = 0x40000a14;
esp_rom_spiflash_config_param       = 0x40000a50;
Cache_Invalidate_DCache_All         = 0x400016e0;
rom_Cache_Suspend_DCache            = 0x400018b4;
Cache_Resume_DCache                 = 0x400018c0;
Cache_MMU_Init                      = 0x40001998;
Cache_Dbus_MMU_Set                  = 0x400019b0;
Cache_Ibus_MMU_Set                  = 0x400019a4;
Cache_Invalidate_ICache_All         = 0x400016d4;
Cache_Disable_ICache                = 0x4000186c;
Cache_Enable_ICache                 = 0x40001878;
rom_Cache_Suspend_ICache            = 0x4000189c;
Cache_Resume_ICache                 = 0x400018a8;
Cache_Set_IDROM_MMU_Size            = 0x40001914;
rom_config_instruction_cache_mode   = 0x40001a1c;
rom_spiflash_legacy_data            = 0x3fceffe4;
