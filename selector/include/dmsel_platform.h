/**
 * @file dmsel_platform.h
 * @brief What the selector firmware takes from the platform
 *
 *  - selector/arch/<arch>: the core - the reset handler and the vectors, the jump into an image (dmsel_arch_jump)
 *  - selector/mcu/<series>/<mcu>: the chip - the flash controller (dmsel_mcu_erase, dmsel_mcu_program), the watchdog;
 *          its dmsel_mcu.h defines DMSEL_MCU_FLASH_ADDRESS
 *  - the board: the layout of the flash, from configs/board/<board>/board.cmake of dmboot (fw/dmsel_layout.h.in); the memory
 *          map and the entry are in configs/mcu/.../selector.ld and configs/arch/.../selector.ld
 * The `user` of the port is the layout (the mcu uses it to erase and program the store only).
 */
#ifndef DMSEL_PLATFORM_H
#define DMSEL_PLATFORM_H

#include <stdint.h>
#include "dmsel.h"

#ifdef __cplusplus
extern "C" {
#endif

// arch
void dmsel_arch_jump( void* user, uint32_t vector_address );
void dmsel_arch_idle( void );                       //!< Waits for an interrupt

// mcu
int  dmsel_mcu_erase( void* user, uint32_t offset, uint32_t size );
int  dmsel_mcu_program( void* user, uint32_t offset, const void* data, uint32_t size );
void dmsel_mcu_watchdog_start( void* user, uint32_t timeout_ms );

// mcu, optional (weak defaults in main.c): a chip without a debug probe that reads the log from the RAM has to bring the text out
void dmsel_mcu_init( void );                        //!< The first thing main() does: the clocks, the watchdogs, the flash, ...
void dmsel_mcu_console( const char* text );         //!< Every line of the log goes here as well
void dmsel_mcu_idle( void );                        //!< One round of the loop the selector stays in when nothing can be started
/** What has to be done before the jump into a bank (the image is not in the memory of the chip yet: the MMU, the cache).
 *  @param address  the entry, in the memory of the layout (flash_address + offset); @return the address to jump to, 0: failed */
uint32_t dmsel_mcu_prepare_jump( void* user, uint32_t address );

#ifdef __cplusplus
}
#endif

#endif /* DMSEL_PLATFORM_H */
