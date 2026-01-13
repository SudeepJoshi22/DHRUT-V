.section .text
.globl _start
_start:

    # Initialize some GPRs using only addi
    addi x5, x0, 5
    addi x6, x0, 6
    addi x7, x0, 7

    # Test 1: Basic nested JAL + JALR return (imm=0)
    jal ra, level1

    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0

back_main:
    addi x8, x0, 8              # Reached back from level1

level1:
    addi x9, x0, 9
    jal ra, level2
back_level1:
    addi x10, x0, 10            # Reached back from level2
    jalr x0, ra, 0              # Return to back_main

level2:
    addi x11, x0, 11
    jalr x0, ra, 0              # Return to back_level1

    # Test 2: JAL with rd != ra (link to x12)
    jal x12, level3
back_jal_rd:
    addi x13, x0, 13            # Reached back

level3:
    addi x14, x0, 14
    jalr x0, x12, 0             # Return using the link in x12

    # Test 3: JALR with non-zero even imm (skip 1 instruction = +4 bytes)
    jal ra, skip_sub
skip_this:
    addi x15, x0, -1            # Should be skipped (was 0xdead → too big)
reach_here:
    addi x16, x0, 16            # Reached if skip correct

skip_sub:
    addi x17, x0, 17
    jalr x0, ra, 4              # ra points to skip_this, +4 reaches reach_here

    # Test 4: JALR with odd imm (tests the & ~1 clearing of bit 0)
    jal ra, odd_skip_sub
odd_skip_this:
    addi x18, x0, -1            # Should be skipped (was 0xbad → too big)
odd_reach_here:
    addi x19, x0, 19            # Reached if & ~1 works correctly

odd_skip_sub:
    addi x20, x0, 20
    jalr x0, ra, 5              # ra + 5 (odd sum) & ~1 = ra + 4 → odd_reach_here

    # Test 5: JALR with rd != x0 (tests linking in JALR)
    jal ra, link_sub
link_skip_this:
    addi x21, x0, -1            # Skipped (was 0xbad → too big)
link_reach_here:
    addi x22, x0, 22            # Reached

link_sub:
    addi x23, x0, 23
    jalr x24, ra, 4             # Links pc+4 into x24, jumps to link_reach_here

    # End of test - infinite loop
end_loop:
    j end_loop
