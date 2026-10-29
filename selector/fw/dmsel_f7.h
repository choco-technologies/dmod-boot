#ifndef DMSEL_F7_H
#define DMSEL_F7_H

#include <stdint.h>

/** The sector of the store (S1) - the only one that this port erases and programs */
#define DMSEL_F7_STORE_OFFSET   0x08000u
#define DMSEL_F7_STORE_SIZE     0x08000u

int  dmsel_f7_erase( void* user, uint32_t offset, uint32_t size );
int  dmsel_f7_program( void* user, uint32_t offset, const void* data, uint32_t size );
void dmsel_f7_jump( void* user, uint32_t vector_address );
void dmsel_f7_watchdog_start( void* user, uint32_t timeout_ms );

#endif
