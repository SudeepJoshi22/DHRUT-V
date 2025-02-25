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
	lui     x5,0x80000
	nop
	nop
	nop
	nop
	addi    x5,x5,12

	lui     x6,0x80000
	addi    x6,x6,16

	nop
	nop
	nop
	nop

	lw a0, 0(t0)

	nop
	nop
	nop
	nop
	nop

	sw a1, 0(t1)

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
    a: .word 0x1234
    b: .word 0xffff
