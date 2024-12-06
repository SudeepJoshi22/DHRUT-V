.global tohost
.global fromhost
.global result
.global _start

#Text Segment

.align 4
.text

#Start your program from here

_start:
	# Initialize registers
	la t2, result     # store address
	ori t0, zero, 1   # cnt = 1
	ori a2, zero, 10  # ten = 10
	ori a0, zero, 0   # out = 0

loop:
	# Calculate sum
	add a0, t0, a0    # out += cnt
	sw a0, 0(t2)      # store out at *store_addr
	addi t0, t0, 1    # cnt++

	# Check loop condition
	blt t0, a2, loop  # branch back if cnt < 10

	# Result should be 0x2d.
	lw t1, 0(t2)      # load the final value
	addi a1, zero, 0x2d  # expected result (0x2d)
	beq t1, a1, pass  # pass if as expected

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
    some_data:	.word 0x10002000 .word 0x20003000  .word 0x40005000 .word 0xabcdefff .word 0xdeadbeef
    tohost: .word 0
    fromhost: .word 0
    result: .word 0
