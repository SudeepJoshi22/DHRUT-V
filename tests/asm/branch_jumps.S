# Simple Branch and Jump Test
.section .text
.globl _start

_start:
    # --- Test 1: BEQ ---
    li x5, 10
    li x6, 10
    beq x5, x6, test_bne
    j fail_beq

test_bne:
    # --- Test 2: BNE ---
    li x6, 11
    bne x5, x6, test_blt
    j fail_bne

test_blt:
    # --- Test 3: BLT ---
    li x5, 5
    li x6, 10
    blt x5, x6, test_jal
    j fail_blt

test_jal:
    # --- Test 4: JAL ---
    la x2, jal_ret_point
    jal x1, jal_target
jal_ret_point:
    bne x1, x2, fail_jal
    j test_jalr

jal_target:
    jr x1

test_jalr:
    # --- Test 5: JALR ---
    la x2, jalr_ret_point
    la x6, jalr_target
    jalr x1, x6, 0
jalr_ret_point:
    bne x1, x2, fail_jalr
    j pass

jalr_target:
    jr x1

pass:
    li x10, 1
    j terminate

fail_beq:  li x10, 0x11
           j terminate
fail_bne:  li x10, 0x22
           j terminate
fail_blt:  li x10, 0x33
           j terminate
fail_jal:  li x10, 0x44
           j terminate
fail_jalr: li x10, 0x55
           j terminate

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
