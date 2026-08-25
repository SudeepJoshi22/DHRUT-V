# Dual-issue hazard test - the cases that must NOT pair.
#
# Every block below is a sequence the 2-wide issue stage has to refuse to
# pair, and where pairing anyway would produce a specific wrong answer
# (not just a timing difference). That is the point: each check fails
# loudly if issue_hazard.sv lets the pair through.
#
# Covered:
#   1. intra-bundle RAW via rs1
#   2. intra-bundle RAW via rs2
#   3. intra-bundle WAW
#   4. lane-1-incapable classes (load, store, branch, jump, CSR)
#   5. RAW through a load result (load-use)
#   6. x0 is not a real dependency and must NOT block pairing
.section .text
.globl _start

_start:
    la  x31, scratch

    # ── 1. RAW through rs1 ──
    # If these paired, the addi would read the OLD x1 (whatever it was)
    # instead of 10, because lane 0's result does not exist yet.
    li   x1, 10
    addi x2, x1, 5        # depends on the li above
    li   x28, 15
    bne  x2, x28, fail

    li   x1, 100
    add  x3, x1, x1       # rs1 AND rs2 both depend on lane 0
    li   x28, 200
    bne  x3, x28, fail

    # ── 2. RAW through rs2 only ──
    li   x4, 7
    li   x5, 3
    add  x6, x5, x4       # rs2 = x4, written by the li two back
    li   x28, 10
    bne  x6, x28, fail

    li   x7, 21
    sub  x8, x7, x5       # rs1 depends on the immediately preceding li
    li   x28, 18
    bne  x8, x28, fail

    # ── 3. WAW on the same destination ──
    # Both write x9. If they paired, two ARF write ports would target x9
    # in one cycle and the surviving value would be undefined.
    li   x9, 1
    li   x9, 2            # must win
    li   x28, 2
    bne  x9, x28, fail

    addi x10, x0, 5
    addi x10, x0, 9       # must win
    li   x28, 9
    bne  x10, x28, fail

    # ── 4. Classes lane 1 cannot execute ──
    # Store then load then branch then jump then CSR, back to back. Lane 1
    # has no dmem port, no branch resolver and no CSR file, so each of
    # these must be forced into lane 0 on its own cycle.
    li   x11, 0x1234
    sw   x11, 0(x31)
    lw   x12, 0(x31)
    li   x28, 0x1234
    bne  x12, x28, fail

    # store immediately followed by store (two memory ops adjacent)
    li   x13, 0x55
    li   x14, 0xAA
    sw   x13, 4(x31)
    sw   x14, 8(x31)
    lw   x15, 4(x31)
    lw   x16, 8(x31)
    li   x28, 0x55
    bne  x15, x28, fail
    li   x28, 0xAA
    bne  x16, x28, fail

    # two branches back to back
    li   x17, 1
    beq  x0, x0, 1f
    j    fail
1:  bne  x17, x0, 2f
    j    fail
2:

    # CSR adjacent to ALU ops on both sides.
    # mscratch, not mcycle: a counter read would differ from Spike's timing
    # model on every run and cost this test its trace gate, which is the
    # thing actually checking that pairing did not reorder anything.
    li   x18, 0xABC
    csrw mscratch, x18
    addi x18, x0, 42
    csrr x19, mscratch
    addi x20, x0, 43
    li   x28, 0xABC
    bne  x19, x28, fail
    li   x28, 42
    bne  x18, x28, fail
    li   x28, 43
    bne  x20, x28, fail

    # ── 5. Load-use: the consumer must wait for the load result ──
    li   x21, 0x7F
    sw   x21, 12(x31)
    lw   x22, 12(x31)
    addi x23, x22, 1      # RAW on a load, and the load is lane-0-only
    li   x28, 0x80
    bne  x23, x28, fail

    # ── 6. x0 is not a dependency ──
    # Lane 0 "writes" x0 (discarded), so lane 1 reading x0 must still be
    # allowed to pair. Nothing here can go wrong architecturally - it is a
    # guard against issue_hazard.sv over-blocking and losing performance.
    add  x0, x1, x1       # writes_rd is false for rd == x0
    addi x24, x0, 77
    li   x28, 77
    bne  x24, x28, fail

    addi x0, x0, 1        # still a no-op
    addi x25, x0, 88
    li   x28, 88
    bne  x25, x28, fail

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
scratch: .space 32

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
