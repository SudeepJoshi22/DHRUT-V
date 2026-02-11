.section .text
.globl _start
_start:
    # Write then read back one word
    la   t0, test_word
    li   t1, 0x12345678
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, fail

pass:
    # Spike-style: LSB=1 terminates; upper bits are exit code (0 => PASS),
    # so PASS is value 1. [page:0]
    la   t0, tohost
    li   t1, 1
    sw   t1, 0(t0)
    sw   x0, 4(t0)          # common companion store used by riscv-test-env [page:1]
1:  j    1b

fail:
    # FAIL: pick a nonzero code (here code=1), encode as (code<<1)|1. [page:0]
    li   t1, 1
    slli t1, t1, 1
    ori  t1, t1, 1
    la   t0, tohost
    sw   t1, 0(t0)
    sw   x0, 4(t0)          # common companion store used by riscv-test-env [page:1]
2:  j    2b


.section .data
.align 2
test_word:
    .word 0

# If your build already pulls in riscv-test-env (riscv_test.h) or another file that
# defines tohost/fromhost, REMOVE the block below to avoid duplicate symbols. [page:1]
.pushsection .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
.popsection
