/**
 * @file board.c
 * @brief STM32F746G-DISCO: the layout of the flash
 *
 * Flash:  S0 selector | S1 store (state of the banks, persistent items) | S2, S3 file systems of the banks |
 *         S4+S5 bank A (384 kB) | S6+S7 bank B (384 kB of the 512 kB)
 * (the same banks as configs/board/stm32f746g-disco/board.cmake of dmboot: DMBOOT_BANK_*)
 */
#include "dmsel_platform.h"
#include "dmsel_mcu.h"
#include "dmsel_board.h"

#ifndef DMSEL_WATCHDOG_MS
#define DMSEL_WATCHDOG_MS       0       // The firmware has to feed the watchdog from the moment it starts: 0 until it does
#endif

const dmsel_layout_t dmsel_board_layout =
{
    .flash_address = DMSEL_MCU_FLASH_ADDRESS,
    .store_offset = DMSEL_BOARD_STORE_OFFSET,
    .store_size = DMSEL_BOARD_STORE_SIZE,
    .bank_count = 2,
    .banks = { { 0x20000u, 0x60000u }, { 0x80000u, 0x60000u } },
    .max_tries = 3,
    .watchdog_ms = DMSEL_WATCHDOG_MS,
};
