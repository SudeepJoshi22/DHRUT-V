# Minimal bare-metal C runtime start file.
#
# Sets up the stack, zeroes .bss, calls main(), then reports main()'s
# return value through the same `tohost` convention every assembly test
# in tests/asm already uses (bit0=1 -> done, bits[31:1]=exit code, 0=pass).
.section .text.init
.globl _start

_start:
    la sp, _stack_top

    # Zero .bss/.sbss (bounds provided by tests/linker_c.ld)
    la t0, _sbss
    la t1, _ebss
zero_bss:
    bge t0, t1, zero_bss_done
    sw  x0, 0(t0)
    addi t0, t0, 4
    j   zero_bss
zero_bss_done:

    call main

    # a0 holds main()'s return value; 0 == pass
    slli a0, a0, 1
    ori  a0, a0, 1
    la   t0, tohost
    sw   a0, 0(t0)
    sw   x0, 4(t0)
spin:
    j spin

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
