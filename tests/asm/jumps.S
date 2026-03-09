# Self-checking Jumps test
.section .text
.globl _start

_start:
    # ───────────────────────────────────────────────
    # Test 1: Nested JAL + JALR Return
    # ───────────────────────────────────────────────
    jal ra, level1
    # Check if we reached back here
    li x1, 8
    bne x8, x1, fail_nested
    
    # ───────────────────────────────────────────────
    # Test 2: JAL with custom link register
    # ───────────────────────────────────────────────
    la x13, level3_ret
    jal x12, level3
level3_ret:
    bne x12, x13, fail_custom_link
    
    # ───────────────────────────────────────────────
    # Test 3: JALR with immediate offset and bit-0 clearing
    # ───────────────────────────────────────────────
    la x6, jalr_target
    addi x6, x6, -4
    jalr ra, x6, 4              # Should jump to jalr_target
    j fail_jalr_imm

jalr_target:
    # Test JALR & ~1
    la x6, jalr_target_odd
    addi x6, x6, 1              # Make it odd
    jalr x0, x6, 0              # Bit 0 should be cleared
    j fail_jalr_align

jalr_target_odd:
    # Success reaching here
    j tests_passed

# --- Subroutines ---

level1:
    li x9, 9
    jal ra, level2
    li x10, 10
    li x8, 8                    # Mark reaching back to main
    jr ra

level2:
    li x11, 11
    jr ra

level3:
    li x14, 14
    jr x12

tests_passed:
    li x10, 1
    j terminate

fail_nested:      li x10, 0x11
                  j fail
fail_custom_link: li x10, 0x22
                  j fail
fail_jalr_imm:    li x10, 0x33
                  j fail
fail_jalr_align:  li x10, 0x44
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
