MEMORY { ROM (rx) : ORIGIN = 0x00000000, LENGTH = 512K  RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 256K }
_estack = ORIGIN(RAM) + LENGTH(RAM);
SECTIONS {
  .vectors : { KEEP(*(.vectors)) } > ROM
  .text : { *(.text*) *(.rodata*) } > ROM
  .data : { *(.data*) } > RAM AT > ROM
  .bss : { *(.bss*) *(COMMON) } > RAM
}
