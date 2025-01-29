.global tohost
.global fromhost
.global result
.global _start

#Text Segment

.align 4
.text

#Start your program from here
# RISC-V RV32I Assembly Code

_start:
    # U-Type Instructions
    lui x1, 0x12345       # Load upper immediate to x1 (set high bits of x1)
    auipc x2, 0x200       # Add PC-relative offset to x2
    
    nop 
    nop
    # R-Type Instructions (No dependencies between instructions)
    add x3, x1, x2        # x3 = x1 + x2
    sub x4, x1, x2        # x4 = x1 - x2
    xor x5, x3, x4        # x5 = x3 XOR x4
    and x6, x1, x2        # x6 = x1 AND x2
    or  x7, x3, x5        # x7 = x3 OR x5
    sll x8, x2, x1        # x8 = x2 << x1 (logical shift left)
    srl x9, x2, x1        # x9 = x2 >> x1 (logical shift right)
    sra x10, x2, x1       # x10 = x2 >> x1 (arithmetic shift right)
    slt x11, x1, x2       # x11 = (x1 < x2) ? 1 : 0

    # I-Type Instructions (No dependencies between instructions)
    addi x12, x0, 123     # x12 = x0 + 123 (immediate add)
    xori x13, x0, 456     # x13 = x0 XOR 456
    andi x14, x0, 789     # x14 = x0 AND 789
    ori  x15, x0, 1023    # x15 = x0 OR 1023
    slli x16, x0, 5       # x16 = x0 << 5 (immediate logical shift left)
    srli x17, x0, 3       # x17 = x0 >> 3 (immediate logical shift right)
    srai x18, x0, 2       # x18 = x0 >> 2 (immediate arithmetic shift right)
    slti x19, x0, 100     # x19 = (x0 < 100) ? 1 : 0

    # End of the program
    nop                   # No operation
    nop                   # Add extra no-ops to ensure the pipeline is clear


fail:
	la t2, tohost
	li a3, 3
	sw a3, 0(t2)
	1: j 1b # wait for termination
	
pass:
	la t2, tohost
	li a3, 1
	sw a3, 0(t2)
	1: j 1b # wait for termination
	
	
#Data Segment

.align 4
.data
    tohost: .word 0
    fromhost: .word 0
    result: .word 0
