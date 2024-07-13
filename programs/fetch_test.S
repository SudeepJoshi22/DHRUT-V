.global tohost
.global fromhost
.global result
.globl _start

#Text Segment

.align 4
.text

_start:
    # Initial setup
    li x1, 0x100   # Load immediate value 0x100 into register x1
    li x2, 0x200   # Load immediate value 0x200 into register x2
    li x3, 0x300   # Load immediate value 0x300 into register x3
    li x4, 0x400   # Load immediate value 0x400 into register x4
    li x5, 0x500   # Load immediate value 0x500 into register x5
    li x6, 0       # Loop counter

loop_start:
    # Normal instructions
    add x10, x1, x2   # x10 = x1 + x2
    sub x11, x3, x4   # x11 = x3 - x4
    and x12, x1, x5   # x12 = x1 & x5
    or  x13, x2, x3   # x13 = x2 | x3
    xor x14, x4, x5   # x14 = x4 ^ x5

    # Branch instructions
    beq x6, x0, branch_taken     # If x6 == 0, branch to branch_taken
    addi x6, x6, 1               # Increment loop counter
    bne x6, x5, branch_not_taken # If x6 != x5, branch to branch_not_taken

branch_not_taken:
    # Normal instructions after not taken branch
    add x15, x1, x2   # x15 = x1 + x2
    sub x16, x3, x4   # x16 = x3 - x4
    and x17, x1, x5   # x17 = x1 & x5
    or  x18, x2, x3   # x18 = x2 | x3
    xor x19, x4, x5   # x19 = x4 ^ x5
    j loop_end        # Jump to loop_end

branch_taken:
    # Normal instructions after taken branch
    add x20, x1, x2   # x20 = x1 + x2
    sub x21, x3, x4   # x21 = x3 - x4
    and x22, x1, x5   # x22 = x1 & x5
    or  x23, x2, x3   # x23 = x2 | x3
    xor x24, x4, x5   # x24 = x4 ^ x5

loop_end:
    # Loop control
    li x7, 10         # Load immediate value 10 into register x7
    blt x6, x7, loop_start # If x6 < 10, branch to loop_start

    # End program
    li x10, 0x1000    # Arbitrary end of program indicator
    j pass       
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
