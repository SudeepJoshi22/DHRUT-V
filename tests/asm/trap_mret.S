# Self-checking mstatus.MIE/MPIE save-restore test across trap entry + mret.
# Sets MIE=1 before trapping; the handler checks that trap entry cleared
# MIE and set MPIE<=old MIE (1); after mret, mainline checks MIE was
# restored to 1.
.section .text
.globl _start

_start:
    li x10, 0

    la t0, trap_handler
    csrw mtvec, t0

    li t0, 0x8            # MIE bit (bit 3)
    csrs mstatus, t0

    csrr t1, mstatus
    andi t1, t1, 0x8
    beqz t1, fail_1        # MIE must read back as 1 before the trap

    li x20, 0             # handler-ran marker

ecall_instr:
    ecall

    csrr t1, mstatus       # back from mret: MIE must be restored to 1
    andi t1, t1, 0x8
    beqz t1, fail_2

    li t2, 1
    bne x20, t2, fail_3

pass:
    li x10, 1
    j terminate

fail_1: li x10, 0x11
        j fail
fail_2: li x10, 0x12
        j fail
fail_3: li x10, 0x13
        j fail

trap_handler:
    csrr t1, mstatus
    andi t2, t1, 0x8       # MIE must be cleared on trap entry
    bnez t2, fail_handler_mie

    andi t2, t1, 0x80      # MPIE must hold the pre-trap MIE value (1)
    beqz t2, fail_handler_mpie

    li   x20, 1

    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    mret

fail_handler_mie:  li x10, 0x21
                    j fail
fail_handler_mpie: li x10, 0x22
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
