# A taken branch and dependent operations after divide must observe its result.
.section .text
.globl _start
_start:
    li s0, 27000000
    li s1, 10
    li s2, 2700000
    divu s3, s0, s1
    bgeu s0, s1, taken
    j fail
taken:
    bne s3, s2, fail
    # Preserve pending forwarding protection across that redirect too.
    li s3, 99
    remu s3, s0, s1
    bgeu s0, s1, remainder
    j fail
remainder:
    bnez s3, fail
    # Younger WAW must wait, or the older divide overwrites the final 99.
    divu s3, s0, s1
    li s3, 99
    li s4, 99
    bne s3, s4, fail
    # A following load cannot lose its result to MDU's retire priority.
    la t0, scratch
    divu s3, s0, s1
    lw s4, 0(t0)
    li s5, 123
    bne s4, s5, fail
    bne s3, s2, fail
    li a0, 1
    j finish
fail:
    li a0, 3
finish:
    la t0, tohost
    sw a0, 0(t0)
    sw zero, 4(t0)
1:  j 1b
.section .data
.align 2
scratch: .word 123
.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost: .dword 0
.size tohost, 8
.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
