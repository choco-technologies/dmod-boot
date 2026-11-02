/*
 * The sections of dmboot on the ESP32-S3 (instead of linker/common.ld: the code and the read-only data are not in one place
 * here). The memory map is mcu.ld, the image of the bank is described in docs/esp32s3-selector.md.
 *
 * The image of the bank, in the order of the load addresses (the code window of the instruction bus, 0x43000000+):
 *   .text     the code, VMA = LMA; the first instruction is the entry of the image (offset 0x200)
 *   .rodata   the read-only data and the embedded images (the file systems, ...): linked for the data window (0x3D000000+),
 *             the same bytes (the instruction bus cannot read bytes)
 *   .iram     the vectors and the code that must be in the RAM: copied to the IRAM by the start
 *   .data     copied to the RAM by the start
 */
IMAGE_CODE      = 0x43000000;
IMAGE_DATA      = 0x3D000000;
CODE_TO_DATA    = IMAGE_CODE - IMAGE_DATA;      /* the data bus reads what the instruction bus fetches, at this distance */
IRAM_TO_DRAM    = 0x6f0000;                     /* the instruction bus of the internal RAM is this far from the data bus */

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

__stack_size__    = 8192;
__logs_size__     = 8192;

PROVIDE(__stack_size__ = __stack_size__);
PROVIDE(__logs_size__  = __logs_size__ );

SECTIONS
{
   .text : ALIGN(4)
   {
      __text_start__ = .;
      PROVIDE(__text_start__ = __text_start__);
      KEEP(*(.vectors))                         /* Reset_Handler: the entry of the image */
      KEEP(*(.startup.literal .startup.text))
      *(.literal .literal.* .text .text.* .gnu.linkonce.t.* .gnu.linkonce.literal.*)
      . = ALIGN(4);
      KEEP(*(.init.literal .init))
      KEEP(*(.fini.literal .fini))
      . = ALIGN(16);
      __text_end__ = .;
      PROVIDE(__text_end__ = __text_end__);
   } > rom AT > rom

   _rodata_lma = .;
   .rodata (_rodata_lma - CODE_TO_DATA) : AT(_rodata_lma)
   {
      __rodata_start__ = .;
      _flash_rodata_start = .;
      *(.rodata .rodata.* .gnu.linkonce.r.*)
      *(.srodata .srodata.*)

      /* (crtbegin.o refers to the frame tables; nothing unwinds the stack here) */
      . = ALIGN(4);
      *(.eh_frame)
      *(.gcc_except_table .gcc_except_table.*)

      . = ALIGN(4);
      __preinit_array_start__ = .;
      KEEP(*(.preinit_array))
      . = ALIGN(4);
      __preinit_array_end__ = .;
      __init_array_start__ = .;
      KEEP(*(SORT(.init_array.*)))
      KEEP(*(.init_array))
      . = ALIGN(4);
      __init_array_end__ = .;
      __fini_array_start__ = .;
      KEEP(*(.fini_array))
      KEEP(*(SORT(.fini_array.*)))
      . = ALIGN(4);
      __fini_array_end__ = .;

      /* The port of FreeRTOS copies this for every task (thread-local storage): nothing here uses it */
      . = ALIGN(16);
      _thread_local_start = .;
      _thread_local_end = .;

      . = ALIGN(16);
      __startup_dmp_start = .;
      KEEP(*(.embedded.startup_dmp))
      __startup_dmp_end = .;
      __startup_dmp_size = __startup_dmp_end - __startup_dmp_start;

      . = ALIGN(16);
      __user_data_start = .;
      KEEP(*(.embedded.user_data))
      __user_data_end = .;
      __user_data_size = __user_data_end - __user_data_start;

      . = ALIGN(16);
      __modules_dmp_start = .;
      KEEP(*(.embedded.modules_dmp))
      __modules_dmp_end = .;
      __modules_dmp_size = __modules_dmp_end - __modules_dmp_start;

      . = ALIGN(16);
      __root_fs_start = .;
      KEEP(*(.embedded.root_fs))
      __root_fs_end = .;
      __root_fs_size = __root_fs_end - __root_fs_start;

      . = ALIGN(16);
      __config_fs_start = .;
      KEEP(*(.embedded.config_fs))
      __config_fs_end = .;
      __config_fs_size = __config_fs_end - __config_fs_start;

      . = ALIGN(16);
      __eviews_fs_start = .;
      KEEP(*(.embedded.eviews_fs))
      __eviews_fs_end = .;
      __eviews_fs_size = __eviews_fs_end - __eviews_fs_start;

      . = ALIGN(16);
      __license_fs_start = .;
      KEEP(*(.embedded.license_fs))
      __license_fs_end = .;
      __license_fs_size = __license_fs_end - __license_fs_start;

      . = ALIGN(16);
   }
   PROVIDE(_flash_rodata_align = 16);
   PROVIDE(__text_start__ = __text_start__);

   /* The vectors of the exceptions (VECBASE) and what has to run from the RAM: copied there by the start. The offsets are
      those of the core (XCHAL_*_VECOFS of xtensa/config/core-isa.h); the vector table is aligned to 1 kB. */
   .iram : AT(ALIGN(LOADADDR(.rodata) + SIZEOF(.rodata), 16))
   {
      _iram_start = ABSOLUTE(.);
      _vector_table = ABSOLUTE(.);
      . = 0x0;
      KEEP(*(.WindowVectors.text));
      . = 0x180;
      KEEP(*(.Level2InterruptVector.text));
      . = 0x1c0;
      KEEP(*(.Level3InterruptVector.text));
      . = 0x200;
      KEEP(*(.Level4InterruptVector.text));
      . = 0x240;
      KEEP(*(.Level5InterruptVector.text));
      . = 0x280;
      KEEP(*(.DebugExceptionVector.text));
      . = 0x2c0;
      KEEP(*(.NMIExceptionVector.text));
      . = 0x300;
      KEEP(*(.KernelExceptionVector.text));
      . = 0x340;
      KEEP(*(.UserExceptionVector.text));
      . = 0x3C0;
      KEEP(*(.DoubleExceptionVector.text));
      . = 0x400;
      *(.*Vector.literal)
      *(.UserEnter.literal)
      *(.UserEnter.text)
      . = ALIGN(16);
      *(.iram1.literal .iram1 .iram1.*)
      . = ALIGN(16);
      _iram_end = ABSOLUTE(.);
      PROVIDE(_iram_text_end = _iram_end);   /* the handler of the 8/16-bit accesses (xtensa_loadstore_handler.S) */
   } > iram
   /* where the start reads them from and writes them to: the data bus */
   _iram_load_d  = LOADADDR(.iram) - CODE_TO_DATA;
   _iram_start_d = _iram_start - IRAM_TO_DRAM;
   _iram_end_d   = _iram_end - IRAM_TO_DRAM;

   /* The log ring buffer first in the RAM */
   .logs (NOLOAD) :
   {
      . = ALIGN(__logs_size__);
      __logs_start__ = .;
      PROVIDE(__logs_start__ = __logs_start__);
      . = __logs_start__ + __logs_size__;
      __logs_end__ = .;
      PROVIDE(__logs_end__ = __logs_end__);
   } > ram

   .data : AT(ALIGN(LOADADDR(.iram) + SIZEOF(.iram), 16))
   {
      . = ALIGN(4);
      __data_init_start__ = LOADADDR(.data);
      __data_start__ = .;
      PROVIDE(__data_start__ = __data_start__);

      *(.data .data.* .gnu.linkonce.d.*)
      *(.sdata .sdata.*)

      /* dmod-system.ld of dmod: the input and output tables of the system */
      . = ALIGN(16);
      __inputs_start = .;
      PROVIDE(__dmod_inputs_start = .);
      KEEP(*(.dmod.inputs))
      __inputs_end = .;
      PROVIDE(__dmod_inputs_end = .);
      __inputs_size = __inputs_end - __inputs_start;
      PROVIDE(__dmod_inputs_size = __inputs_end - __inputs_start);

      . = ALIGN(16);
      __outputs_start = .;
      PROVIDE(__dmod_outputs_start = .);
      KEEP(*(.dmod.outputs))
      __outputs_end = .;
      PROVIDE(__dmod_outputs_end = .);
      __outputs_size = __outputs_end - __outputs_start;
      PROVIDE(__dmod_outputs_size = __outputs_end - __outputs_start);

      . = ALIGN(4);
      __data_end__ = .;
      PROVIDE(__data_end__ = __data_end__);
   } > ram
   __data_init_start_d = __data_init_start__ - CODE_TO_DATA;

   .bss (NOLOAD) :
   {
      . = ALIGN(4);
      __bss_start__ = .;
      PROVIDE(__bss_start__ = __bss_start__);
      *(.bss .bss.* .gnu.linkonce.b.*)
      *(.sbss .sbss.*)
      . = ALIGN(4);
      *(COMMON);
      . = ALIGN(4);
      __bss_end__ = .;
      PROVIDE(__bss_end__ = __bss_end__);
   } > ram

   .stack (NOLOAD) :
   {
      . = ALIGN(16);
      __stack_start__ = .;
      PROVIDE(__stack_start__ = __stack_start__);
      . += __stack_size__;
      . = ALIGN(16);
      __stack_end__ = .;
      PROVIDE(__stack_end__ = __stack_end__);
   } > ram

   . = ALIGN(4);
   __heap_start__ = .;
   PROVIDE(__heap_start__ = __heap_start__);
   __heap_end__ = __ram_end__;
   PROVIDE(__heap_end__ = __heap_end__);
   PROVIDE(end = __heap_start__);               /* sbrk of the C library (nothing allocates with it) */

   ASSERT(LOADADDR(.data) + SIZEOF(.data) <= __rom_end__, "the image does not fit in the bank")

   .stab             0 (NOLOAD) : { *(.stab) }
   .stabstr          0 (NOLOAD) : { *(.stabstr) }
   .debug               0 : { *(.debug) }
   .line                0 : { *(.line) }
   .debug_srcinfo       0 : { *(.debug_srcinfo) }
   .debug_sfnames       0 : { *(.debug_sfnames) }
   .debug_aranges       0 : { *(.debug_aranges) }
   .debug_pubnames      0 : { *(.debug_pubnames) }
   .debug_info          0 : { *(.debug_info .gnu.linkonce.wi.*) }
   .debug_abbrev        0 : { *(.debug_abbrev) }
   .debug_line          0 : { *(.debug_line) }
   .debug_frame         0 : { *(.debug_frame) }
   .debug_str           0 : { *(.debug_str) }
   .debug_loc           0 : { *(.debug_loc) }
   .debug_macinfo       0 : { *(.debug_macinfo) }
   .debug_weaknames     0 : { *(.debug_weaknames) }
   .debug_funcnames     0 : { *(.debug_funcnames) }
   .debug_typenames     0 : { *(.debug_typenames) }
   .debug_varnames      0 : { *(.debug_varnames) }
   .debug_ranges        0 : { *(.debug_ranges) }
   .debug_line_str      0 : { *(.debug_line_str) }
   .debug_rnglists      0 : { *(.debug_rnglists) }
   .debug_loclists      0 : { *(.debug_loclists) }

   /DISCARD/ : { *(.note.GNU-stack) *(.comment) *(.note.*) *(.xt.*) *(.xtensa.info) }
}
