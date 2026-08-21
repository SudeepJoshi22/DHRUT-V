# Self-checking ECALL trap test.
# Verifies: mcause == 11 (env call from M-mode), mepc == the ecall's own
# PC, mtval == 0, and that mret correctly returns execution to mepc+4
# (the handler advances mepc past the ecall before returning).
.section .text
.globl _start

_start:
    li x10, 0

    la t0, trap_handler
    csrw mtvec, t0

    li x20, 0            # handler-ran marker

ecall_instr:
    ecall
    li t1, 1
    bne x20, t1, fail_1   # handler must have run exactly once

pass:
    li x10, 1
    j terminate

fail_1: li x10, 0x11
        j fail

trap_handler:
    csrr t1, mcause
    li   t2, 11
    bne  t1, t2, fail_handler_cause

    csrr t1, mepc
    la   t2, ecall_instr
    bne  t1, t2, fail_handler_mepc

    csrr t1, mtval
    bnez t1, fail_handler_mtval

    li   x20, 1

    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    mret

fail_handler_cause: li x10, 0x21
                     j fail
fail_handler_mepc:  li x10, 0x22
                     j fail
fail_handler_mtval: li x10, 0x23
                     j fail

fail:
    slli x10, x10, 1
    ori  x10, x10, 1

terminate:
    la t0, tohost
    sw x10, 0(t0)
    sw x0, 4(t0)
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
