ENTRY(_start)

SECTIONS
{
  /* Start everything at address 0x0 */
  . = 0x00000000;

  /* Code */
  .text : {
    *(.text*)
  }

  /* Optional: keep these empty for now */
  .rodata : {
    *(.rodata*)
  }

  .data : {
    *(.data*)
  }

  .bss : {
    *(.bss*)
    *(COMMON)
  }
}
