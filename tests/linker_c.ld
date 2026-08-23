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

  . = ALIGN(4);
  _sbss = .;
  .sbss : { *(.sbss*) *(.scommon) }
  .bss  : { *(.bss*) *(COMMON) }
  _ebss = .;

  . = ALIGN(16);
  . = . + 0x2000;        /* 8KB stack, grows down from _stack_top */
  _stack_top = .;

  _end = .;
}
