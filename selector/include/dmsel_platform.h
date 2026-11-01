/**
 * @file dmsel_platform.h
 * @brief What the selector firmware takes from the platform: configs/arch, configs/mcu and configs/board of the selector
 *
 * The directories follow the configs/ of dmboot (arch/<family>/<core>, mcu/<family>/<mcu>, board/<board>):
 *  - arch: the core - the reset handler and the vectors, the jump into an image (dmsel_arch_jump)
 *  - mcu:  the chip - the flash controller (dmsel_mcu_erase, dmsel_mcu_program), the watchdog, the memory map (mcu.ld);
 *          its dmsel_mcu.h defines DMSEL_MCU_FLASH_ADDRESS
 *  - board: the layout of the flash - the banks and the store (dmsel_board_layout); its dmsel_board.h defines
 *          DMSEL_BOARD_STORE_SIZE
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

// mcu
int  dmsel_mcu_erase( void* user, uint32_t offset, uint32_t size );
int  dmsel_mcu_program( void* user, uint32_t offset, const void* data, uint32_t size );
void dmsel_mcu_watchdog_start( void* user, uint32_t timeout_ms );

// board
extern const dmsel_layout_t dmsel_board_layout;

#ifdef __cplusplus
}
#endif

#endif /* DMSEL_PLATFORM_H */
