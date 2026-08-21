# Self-checking EBREAK trap test.
# Verifies: mcause == 3 (breakpoint), mepc == the ebreak's own PC,
# mtval == mepc (this RTL sets mtval = the faulting PC for ebreak), and
# that mret correctly returns execution past it.
.section .text
.globl _start

_start:
    li x10, 0

    la t0, trap_handler
    csrw mtvec, t0

    li x20, 0            # handler-ran marker

ebreak_instr:
    ebreak
    li t1, 1
    bne x20, t1, fail_1

pass:
    li x10, 1
    j terminate

fail_1: li x10, 0x11
        j fail

trap_handler:
    csrr t1, mcause
    li   t2, 3
    bne  t1, t2, fail_handler_cause

    csrr t1, mepc
    la   t2, ebreak_instr
    bne  t1, t2, fail_handler_mepc

    csrr t1, mtval
    bne  t1, t2, fail_handler_mtval   # mtval must equal ebreak's own PC too

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
