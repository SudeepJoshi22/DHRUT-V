OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;

  .text : { *(.text.init) *(.text*) }   /* code stays contiguous at base */

  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }              /* tohost after code */

  .rodata : { *(.rodata*) }
  .data   : { *(.data*) }
  .sdata  : { *(.sdata*) }
  .sbss   : { *(.sbss*) *(.scommon) }
  .bss    : { *(.bss*) *(COMMON) }
  _end = .;
}
