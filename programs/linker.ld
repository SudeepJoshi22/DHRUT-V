OUTPUT_ARCH("riscv")

ENTRY(_start)

SECTIONS
{
	. = 0x80000000;

	.tohost : ALIGN(0x1000)
	{
		*(.tohost)
	}

	. += 0x1000;
	
	.fromhost : ALIGN(0x1000)
	{
		*(.fromhost)
	}
	
	. += 0x1000;

	.data : ALIGN(0X1000)
	{
		*(.data)
	}
	


	. += 0x1000;
	
	.text : ALIGN(0x1000)
	{
		*(.text)
	}
	
	
}

