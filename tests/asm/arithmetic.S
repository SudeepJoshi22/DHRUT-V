# Self-checking Arithmetic/Logical test
.section .text
.globl _start

_start:
    # ───────────────────────────────────────────────
    # 1. Setup constants and check them
    # ───────────────────────────────────────────────
    li x2, 1
    li x3, 2
    li x4, 10
    li x5, 16
    li x6, -8
    li x7, -4

    # Check setup (just in case 'li' macro/addi is broken)
    addi x1, x0, 1
    bne x1, x2, fail_setup
    
    # ───────────────────────────────────────────────
    # 2. I-type instructions
    # ───────────────────────────────────────────────
    
    # ADDI
    addi x21, x4, 52               # 10 + 52 = 62
    li x1, 62
    bne x21, x1, fail_addi

    # SLTI / SLTIU
    slti x23, x4, 15               # 10 < 15 = 1
    li x1, 1
    bne x23, x1, fail_slti
    
    slti x24, x4, 5                # 10 < 5 = 0
    li x1, 0
    bne x24, x1, fail_slti

    # XORI / ORI / ANDI
    li x10, 0xAAAAAAAA
    xori x28, x10, -1              # ~0xAAAAAAAA = 0x55555555
    li x1, 0x55555555
    bne x28, x1, fail_logic_imm

    # SLLI / SRLI / SRAI
    slli x12, x5, 3                # 16 << 3 = 128
    li x1, 128
    bne x12, x1, fail_shift_imm

    li x10, 0xAAAAAAAA
    srli x14, x10, 4               # 0xAAAAAAAA >> 4 = 0x0AAAAAAA
    li x1, 0x0AAAAAAA
    bne x14, x1, fail_shift_imm

    # ───────────────────────────────────────────────
    # 3. R-type instructions
    # ───────────────────────────────────────────────
    
    # ADD / SUB
    add  x17, x4, x5               # 10 + 16 = 26
    li x1, 26
    bne x17, x1, fail_r_type

    sub  x18, x5, x4               # 16 - 10 = 6
    li x1, 6
    bne x18, x1, fail_r_type

    # SLL / SRL / SRA
    sll  x19, x5, x3               # 16 << 2 = 64
    li x1, 64
    bne x19, x1, fail_r_type

    # XOR / OR / AND
    li x10, 0xAAAAAAAA
    li x11, 0x55555555
    xor  x22, x10, x11             # 0xFFFFFFFF
    li x1, 0xFFFFFFFF
    bne x22, x1, fail_r_type

    # ───────────────────────────────────────────────
    # 4. U-type instructions
    # ───────────────────────────────────────────────
    lui   x27, 0x12345             # x27 = 0x12345000
    li    x1, 0x12345000
    bne   x27, x1, fail_u_type

    # AUIPC
    # We check if PC is roughly correct
    # 80000000 + offset
    auipc x29, 0                   
    srli  x29, x29, 12             # Should be 0x80000
    li    x1, 0x80000
    bne   x29, x1, fail_u_type

pass:
    li x10, 1
    j terminate

fail_setup:     li x10, 0x11
                j fail
fail_addi:      li x10, 0x22
                j fail
fail_slti:      li x10, 0x33
                j fail
fail_logic_imm: li x10, 0x44
                j fail
fail_shift_imm: li x10, 0x55
                j fail
fail_r_type:    li x10, 0x66
                j fail
fail_u_type:    li x10, 0x77
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
