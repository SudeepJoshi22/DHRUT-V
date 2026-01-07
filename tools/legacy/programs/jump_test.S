.global tohost
.global fromhost
.global result
.globl _start

#Text Segment

.align 4
.text

#Start your program from here

_start:

	li t0, 100
	li t1, 200
	beq t0,t1,fail
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
