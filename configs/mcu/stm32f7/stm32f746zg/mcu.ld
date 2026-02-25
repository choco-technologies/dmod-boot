/*
* STM32F746ZG memory layout:
* - Flash: 1024KB (0x08000000 - 0x080FFFFF)  
* - SRAM1: 320KB (0x20010000 - 0x2006FFFF)
* - DTCM:  64KB (0x20000000 - 0x2000FFFF)
*/

MEMORY
{
    rom   (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
    ram   (rwx) : ORIGIN = 0x20010000, LENGTH = 320K
    dtcm  (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
    ext   (rwx) : ORIGIN = 0x60000000, LENGTH = 0
    dma   (rwx) : ORIGIN = 0x20000000, LENGTH = 0
}