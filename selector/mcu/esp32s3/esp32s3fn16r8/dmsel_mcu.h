#ifndef DMSEL_MCU_H
#define DMSEL_MCU_H

#include <stdint.h>

/** Where the flash is in the memory of the chip (offset 0 of the layout): dmsel_mcu_flash_init() maps all of it there.
 *  It uses the entries 0..255 of the MMU (the table is one for the data bus from 0x3C000000 and for the code bus from
 *  0x42000000: the entry n is the page n of both windows). */
#define DMSEL_MCU_FLASH_ADDRESS 0x3C000000u

/** The window of the image of a bank, the same for every bank: the entries 256.. of the MMU, which the identity mapping above
 *  leaves alone (the table of the selector keeps reading the flash through it while the firmware runs). The image of the bank
 *  (its header first) is seen from the start of the window, by the code bus and by the data bus alike - a firmware is linked
 *  with the code at DMSEL_MCU_IMAGE_CODE + offset in the image and the read-only data at DMSEL_MCU_IMAGE_DATA + offset. */
#define DMSEL_MCU_IMAGE_CODE    0x43000000u
#define DMSEL_MCU_IMAGE_DATA    0x3D000000u

/** Maps the flash into the memory (the cache and its MMU), prepares the ROM's driver for the writes; 0, or negative */
int dmsel_mcu_flash_init( void );

#endif
