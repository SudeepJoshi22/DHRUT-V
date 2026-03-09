# Self-checking Branch test
.section .text
.globl _start

_start:
    # Setup base values
    li x5, 5
    li x6, 6
    li x7, 7
    li x10, -3
    li x20, 0

    # --- GROUP 1: NOT-TAKEN BRANCHES ---

    # BEQ not taken (5 == 6? no)
    beq x5, x6, fail_beq_nt
    # BNE not taken (5 != 5? no)
    bne x5, x5, fail_bne_nt
    # BLT not taken (7 < 5 signed? no)
    blt x7, x5, fail_blt_nt
    # BGE not taken (-3 >= 5? no)
    bge x10, x5, fail_bge_nt
    # BLTU not taken (7 < 5 unsigned? no)
    bltu x7, x5, fail_bltu_nt
    # BGEU not taken (5 >= 7 unsigned? no)
    bgeu x5, x7, fail_bgeu_nt

    # --- GROUP 2: TAKEN BRANCHES ---

    # BEQ taken
    beq x5, x5, 1f
    j fail_beq_t
1:
    # BNE taken
    bne x5, x6, 1f
    j fail_bne_t
1:
    # BLT taken
    blt x5, x7, 1f
    j fail_blt_t
1:
    # BGE taken
    bge x5, x10, 1f
    j fail_bge_t
1:
    # BLTU taken
    li x25, 10
    li x26, -1
    bltu x25, x26, 1f
    j fail_bltu_t
1:
    # BGEU taken
    bgeu x26, x25, 1f
    j fail_bgeu_t
1:

    # Backward branch
    li x30, 1
backward_loop:
    addi x30, x30, -1
    bne x30, x0, backward_loop
    # Reached here = success

pass:
    li x10, 1
    j terminate

fail_beq_nt:  li x10, 0x11
              j fail
fail_bne_nt:  li x10, 0x12
              j fail
fail_blt_nt:  li x10, 0x13
              j fail
fail_bge_nt:  li x10, 0x14
              j fail
fail_bltu_nt: li x10, 0x15
              j fail
fail_bgeu_nt: li x10, 0x16
              j fail

fail_beq_t:   li x10, 0x21
              j fail
fail_bne_t:   li x10, 0x22
              j fail
fail_blt_t:   li x10, 0x23
              j fail
fail_bge_t:   li x10, 0x24
              j fail
fail_bltu_t:  li x10, 0x25
              j fail
fail_bgeu_t:  li x10, 0x26
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
