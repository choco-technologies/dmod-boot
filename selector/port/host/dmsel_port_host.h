/**
 * @file dmsel_port_host.h
 * @brief The flash in RAM, for the tests of the selector on the host
 *
 * It keeps the rules of the real one: erased bytes are 0xFF, programming only on erased words (it fails otherwise), the erase
 * clears whole ranges. fail_after makes the n-th next program (and everything after it) fail half way: a power cut.
 */
#ifndef DMSEL_PORT_HOST_H
#define DMSEL_PORT_HOST_H

#include "dmsel.h"

#define HOST_FLASH_SIZE     (1024u * 1024u)

typedef struct
{
    uint8_t     flash[HOST_FLASH_SIZE];
    int         fail_after;         //!< -1: never; n: the program number n (0 - the next one) is cut and all after it fail
    int         programs;
    int         erases;
    int         program_errors;     //!< Programs refused because the flash was not erased
    uint32_t    jumped_to;          //!< Address of the last jump (0: none)
    char        log[4096];
    dmsel_port_t port;
} host_flash_t;

void host_flash_init( host_flash_t* f );

#endif
