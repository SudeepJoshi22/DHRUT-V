# Check all eight RV32M operations, divide special cases and pipeline dependencies.

.section .text
.globl _start

_start:

    # ── MUL: low half ────────────────────────────────────────────
    li   x1, 6
    li   x2, 7
    mul  x3, x1, x2
    li   x4, 42
    bne  x3, x4, fail

    # low half is interpretation-free: -6 * 7 = -42
    li   x1, -6
    li   x2, 7
    mul  x3, x1, x2
    li   x4, -42
    bne  x3, x4, fail

    # ── MULH / MULHU / MULHSU: the upper half ────────────────────
    # 0x40000000 * 4 = 0x1_00000000 -> high word 1
    li    x1, 0x40000000
    li    x2, 4
    mulh  x3, x1, x2
    li    x4, 1
    bne   x3, x4, fail

    # -1 * -1 = 1, so the signed high half is 0
    li    x1, -1
    li    x2, -1
    mulh  x3, x1, x2
    bnez  x3, fail

    # unsigned: 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001
    li    x1, -1
    li    x2, -1
    mulhu x3, x1, x2
    li    x4, 0xFFFFFFFE
    bne   x3, x4, fail

    # MULHSU: SIGNED rs1 (-1) times UNSIGNED rs2 (0xFFFFFFFF)
    #   -1 * 4294967295 = -4294967295 = 0xFFFFFFFF_00000001
    # The high word is 0xFFFFFFFF. Getting this arm wrong by treating both
    # operands the same way is the classic MULHSU bug -- MULHU above would
    # give 0xFFFFFFFE here, and MULH would give 0.
    li     x1, -1
    li     x2, -1
    mulhsu x3, x1, x2
    li     x4, 0xFFFFFFFF
    bne    x3, x4, fail

    # ── DIV / DIVU / REM / REMU: ordinary ────────────────────────
    li   x1, 100
    li   x2, 7
    div  x3, x1, x2
    li   x4, 14
    bne  x3, x4, fail
    rem  x3, x1, x2
    li   x4, 2
    bne  x3, x4, fail

    # signed division truncates TOWARD ZERO, and the remainder takes the
    # sign of the dividend: -100 / 7 = -14 remainder -2 (not -15 r 5)
    li   x1, -100
    li   x2, 7
    div  x3, x1, x2
    li   x4, -14
    bne  x3, x4, fail
    rem  x3, x1, x2
    li   x4, -2
    bne  x3, x4, fail

    # smaller dividend than divisor -> quotient 0, remainder = dividend
    li   x1, -15
    li   x2, 64
    div  x3, x1, x2
    bnez x3, fail
    rem  x3, x1, x2
    li   x4, -15
    bne  x3, x4, fail

    # unsigned reads the same bits differently: 0xFFFFFFFF / 2
    li   x1, -1
    li   x2, 2
    divu x3, x1, x2
    li   x4, 0x7FFFFFFF
    bne  x3, x4, fail
    remu x3, x1, x2
    li   x4, 1
    bne  x3, x4, fail

    # ── Divide by zero: no trap ──────────────────────────────────
    li   x1, 42
    li   x2, 0
    div  x3, x1, x2
    li   x4, -1
    bne  x3, x4, fail
    divu x3, x1, x2
    li   x4, -1
    bne  x3, x4, fail
    rem  x3, x1, x2          # remainder is the dividend, untouched
    li   x4, 42
    bne  x3, x4, fail
    remu x3, x1, x2
    li   x4, 42
    bne  x3, x4, fail

    # ── Signed overflow -2^31 / -1: no trap ──────────────────────
    li   x1, 0x80000000
    li   x2, -1
    div  x3, x1, x2          # quotient wraps back to -2^31
    li   x4, 0x80000000
    bne  x3, x4, fail
    rem  x3, x1, x2          # remainder 0
    bnez x3, fail

    # ── Pipeline: dependent M ops back to back ───────────────────
    # x3 comes from a divide and is read by the next instruction. The MDU
    # is not on the bypass network, so the scoreboard has to hold this
    # multiply back until the divide writes back. If it does not, the
    # multiply reads a stale x3.
    li   x1, 1000
    li   x2, 8
    div  x3, x1, x2          # 125
    mul  x5, x3, x3          # 15625, only correct if x3 was waited for
    li   x4, 15625
    bne  x5, x4, fail

    # ── Pipeline: independent work after a long divide ────────────
    # The core serializes issue across the MDU because it has no reorder
    # buffer. These adds check that issue resumes cleanly afterward.
    li   x1, 123456
    li   x2, 3
    div  x7, x1, x2          # 41152, ~32 cycles
    li   x8, 0
    addi x8, x8, 1
    addi x8, x8, 1
    addi x8, x8, 1
    addi x8, x8, 1
    li   x9, 4
    bne  x8, x9, fail
    li   x4, 41152
    bne  x7, x4, fail        # consumed long after dispatch

    # ── Pipeline: an M op between two ALU ops on the same reg ────
    li   x1, 9
    li   x2, 9
    addi x11, x0, 5
    mul  x12, x1, x2         # 81
    addi x11, x11, 5         # independent, retires after the multiply
    li   x4, 81
    bne  x12, x4, fail
    li   x4, 10
    bne  x11, x4, fail

    # A consumer must read the MDU result despite an older bypass value for rd.
    lui  x31, 0xb
    addi x31, x31, 1285      # x31 = 0xb505, now live in the bypass network
    mul  x31, x31, x31       # same register, multi-cycle -> not bypassable
    li   x4, 0x80001219      # 0xb505 * 0xb505, low 32 bits
    bne  x31, x4, fail       # reads x31 immediately after

    # Same hazard, but through a STORE's data operand (rs2) rather than a
    # branch, because the store path reaches readiness by a different
    # route and that is how riscof surfaced it.
    la   x1, scratch
    lui  x30, 0xb
    addi x30, x30, 1285
    mul  x30, x30, x30
    sw   x30, 0(x1)
    lw   x5, 0(x1)
    li   x4, 0x80001219
    bne  x5, x4, fail

pass:
    li x10, 1
    j terminate

fail:
    li x10, 3

terminate:
    la t0, tohost
    sw x10, 0(t0)
    sw x0, 4(t0)
spin:
    j spin

.section .data
.align 4
scratch: .word 0

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
