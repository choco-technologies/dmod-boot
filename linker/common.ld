PROVIDE(__rom_start__ = ORIGIN(rom));
PROVIDE(__rom_size__  = LENGTH(rom));
PROVIDE(__rom_end__   = __rom_start__ + __rom_size__);

PROVIDE(__ram_start__ = ORIGIN(ram));
PROVIDE(__ram_size__  = LENGTH(ram));
PROVIDE(__ram_end__   = __ram_start__ + __ram_size__);

PROVIDE(__ext_start__ = ORIGIN(ext));
PROVIDE(__ext_size__  = LENGTH(ext));
PROVIDE(__ext_end__   = __ext_start__ + __ext_size__);

PROVIDE(__dma_start__ = ORIGIN(dma));
PROVIDE(__dma_size__  = LENGTH(dma));
PROVIDE(__dma_end__   = __dma_start__ + __dma_size__);

ENTRY(Reset_Handler);

__stack_size__    = 4096;
__logs_size__     = 8192;

PROVIDE(__stack_size__ = __stack_size__);
PROVIDE(__logs_size__  = __logs_size__ );

SECTIONS
{
   .text :
   {
      . = ALIGN(4);
      __text_start__ = .;
      PROVIDE(__text_start__ = __text_start__);
      
      . = ALIGN(4);
      KEEP(*(.vectors)) /* Startup code */
      
      . = ALIGN(4);
      
      *(.text .text.* .gnu.linkonce.t.*);
      . = ALIGN(4);
      *(.glue_7t .glue_7);
      . = ALIGN(4);
      *(.rodata .rodata.* .gnu.linkonce.r.*);

      . = ALIGN(4);
      *(.ARM.extab* .gnu.linkonce.armextab.*);   /* exception unwinding information */
      . = ALIGN(4);
      *(.gcc_except_table);                      /* information used for stack unwinding during exception */
      . = ALIGN(4);
      *(.eh_frame_hdr);                          /* additional information about .ex_frame section */
      . = ALIGN(4);
      *(.eh_frame);                              /* information used for stack unwinding during exception */

      . = ALIGN(4);
      KEEP(*(.init));
      . = ALIGN(4);
      __preinit_array_start__ = .;
      KEEP(*(.preinit_array));
      . = ALIGN(4);
      __preinit_array_end__ = .;
      __init_array_start__ = .;
      KEEP(*(SORT(.init_array.*)));
      . = ALIGN(4);
      KEEP(*(.init_array));
      . = ALIGN(4);
      __init_array_end__ = .;
      KEEP(*(.fini));
      . = ALIGN(4);
      __fini_array_start__ = .;
      KEEP(*(.fini_array));
      . = ALIGN(4);
      KEEP(*(SORT(.fini_array.*)));
      . = ALIGN(4);
      __fini_array_end__ = .;

      . = ALIGN(4);
      __text_end__ = .;
      PROVIDE(__text_end__ = __text_end__);
   } > rom AT > rom

   . = ALIGN(4);
   __exidx_start__ = .;
   PROVIDE(__exidx_start__ = __exidx_start__);

   .ARM.exidx :
   {
      *(.ARM.exidx* .gnu.linkonce.armexidx.*);
   } > rom AT > rom                        /* index entries for section unwinding */

   . = ALIGN(4);
   __exidx_end__ = .;
   PROVIDE(__exidx_end__ = __exidx_end__);

   .data :
   {
      . = ALIGN(4);
      __logs_start__ = .;
      . = __logs_start__ + __logs_size__;
      PROVIDE(__logs_start__ = __logs_start__);
      __logs_end__ = .;
      PROVIDE(__logs_end__ = __logs_end__);

      . = ALIGN(4);
      __data_init_start__ = LOADADDR (.data);
      PROVIDE(__data_init_start__ = __data_init_start__);
      __data_start__ = .;
      PROVIDE(__data_start__ = __data_start__);

      . = ALIGN(4);
      *(.data .data.* .gnu.linkonce.d.*)

      . = ALIGN(4);
      __data_end__ = .;
      PROVIDE(__data_end__ = __data_end__);
   } > ram AT > rom

   INCLUDE dmod-system.ld

   . = ALIGN(4);

   .bss :
   {
      . = ALIGN(4);
      __bss_start__ = .;
      PROVIDE(__bss_start__ = __bss_start__);

      . = ALIGN(4);
      *(.bss .bss.* .gnu.linkonce.b.*)
      . = ALIGN(4);
      *(COMMON);

      . = ALIGN(4);
      __bss_end__ = .;
      PROVIDE(__bss_end__ = __bss_end__);
   } > ram AT > ram

   .stack :
   {
      . = ALIGN(8);
      __stack_start__ = .;
      PROVIDE(__stack_start__ = __stack_start__);

      . += __stack_size__;

      . = ALIGN(8);
      __stack_end__ = .;
      PROVIDE(__stack_end__ = __stack_end__);
   } > ram AT > ram

   . = ALIGN(4);
   __heap_start__ = .;
   PROVIDE(__heap_start__ = __heap_start__);

   . = ALIGN(4);
   __heap_end__ = __ram_end__;
   PROVIDE(__heap_end__ = __heap_end__);

   .stab             0 (NOLOAD) : { *(.stab) }
   .stabstr          0 (NOLOAD) : { *(.stabstr) }

   /* DWARF debug sections.
   * Symbols in the DWARF debugging sections are relative to the beginning
   * of the section so we begin them at 0. */
   /* DWARF 1 */
   .debug               0 : { *(.debug) }
   .line                0 : { *(.line) }

   /* GNU DWARF 1 extensions */
   .debug_srcinfo       0 : { *(.debug_srcinfo) }
   .debug_sfnames       0 : { *(.debug_sfnames) }

   /* DWARF 1.1 and DWARF 2 */
   .debug_aranges       0 : { *(.debug_aranges) }
   .debug_pubnames      0 : { *(.debug_pubnames) }

   /* DWARF 2 */
   .debug_info          0 : { *(.debug_info .gnu.linkonce.wi.*) }
   .debug_abbrev        0 : { *(.debug_abbrev) }
   .debug_line          0 : { *(.debug_line) }
   .debug_frame         0 : { *(.debug_frame) }
   .debug_str           0 : { *(.debug_str) }
   .debug_loc           0 : { *(.debug_loc) }
   .debug_macinfo       0 : { *(.debug_macinfo) }

   /* SGI/MIPS DWARF 2 extensions */
   .debug_weaknames     0 : { *(.debug_weaknames) }
   .debug_funcnames     0 : { *(.debug_funcnames) }
   .debug_typenames     0 : { *(.debug_typenames) }
   .debug_varnames      0 : { *(.debug_varnames) }

   .note.gnu.arm.ident  0 : { KEEP(*(.note.gnu.arm.ident)) }
   .ARM.attributes      0 : { KEEP(*(.ARM.attributes)) }
   /DISCARD/            : { *(.note.GNU-stack) }
}