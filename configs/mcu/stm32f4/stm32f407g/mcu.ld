/*
* STM32F407G memory layout:
* - Flash: 1024KB (0x08000000 - 0x080FFFFF)  
* - SRAM1: 112KB (0x20000000 - 0x2001BFFF)
* - SRAM2: 16KB (0x2001C000 - 0x2001FFFF)
* - CCM: 64KB (0x10000000 - 0x1000FFFF) - Core Coupled Memory
*/

MEMORY
{
    rom   (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
    ram   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
    ccm   (rwx) : ORIGIN = 0x10000000, LENGTH = 64K
    ext   (rwx) : ORIGIN = 0x60000000, LENGTH = 0
    dma   (rwx) : ORIGIN = 0x20000000, LENGTH = 0
}