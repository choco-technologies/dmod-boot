/* The selector (selector/): the first sector of the flash (DMSEL_ROM_ORIGIN, DMSEL_ROM_LENGTH come from --defsym: the
   layout of the board), the DTCM is its RAM */
MEMORY
{
    FLASH (rx)  : ORIGIN = DMSEL_ROM_ORIGIN, LENGTH = DMSEL_ROM_LENGTH
    RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}
