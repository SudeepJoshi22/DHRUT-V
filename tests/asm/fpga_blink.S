# FPGA bringup test: drive the onboard LEDs from software.
#
# tests/asm/add.S and friends finish in microseconds, so on hardware you see
# the final state and nothing of the run itself. This test makes execution
# *visible*: it sweeps a counter slowly enough to watch, which is unambiguous
# proof that fetch, decode, ALU, branch and store are all working -- with no
# UART and no peripheral.
#
# How the store reaches an LED: fpga/rtl/cpu_top.sv snoops the dmem write bus
# and latches the low bits of any store to LED_ADDR onto led[5:4]. There is no
# peripheral and no address decoder involved -- the store also lands in RAM,
# harmlessly. See fpga/UART_PLAN.md for the real MMIO work.
#
# Only the low TWO bits reach LEDs, so the visible pattern cycles 00-01-10-11.
# The counter still runs the full 16 steps: a longer count exercises more
# arithmetic and gives the checksum below something worth checking. Pass/fail
# shows separately on led[3]/led[2] via the tohost write.
#
# DELAY_SHIFT sets the dwell time per step and is overridable, because the two
# environments want wildly different values:
#   simulation : EXTRA_CFLAGS=-DDELAY_SHIFT=4 ./tools/simulate.sh fpga_blink
#   hardware   : the default 22 -> ~4.2M delay iterations, roughly a second a
#                step at 27 MHz. Simulating that would take hours.
#
# The test is self-checking (sum of 0..15 == 120) so it is a real test and not
# just a light show -- its retired-instruction trace can be diffed against
# Spike like any other.

#ifndef DELAY_SHIFT
#define DELAY_SHIFT 22
#endif

.equ LED_ADDR,  0x80001FFC   # top word of the 8 KB dmem; move if DMEM_DEPTH grows
.equ LED_STEPS, 16           # full sweep; low 2 bits of each value reach LEDs

.section .text
.globl _start

_start:
    li   x7,  LED_ADDR
    li   x5,  0               # counter, also the LED pattern
    li   x6,  LED_STEPS
    li   x28, 0               # checksum accumulator

cycle:
    sw   x5, 0(x7)            # drive the user LEDs
    add  x28, x28, x5         # accumulate for the self-check

    li   x8, 1
    slli x8, x8, DELAY_SHIFT
delay:
    addi x8, x8, -1
    bne  x8, x0, delay

    addi x5, x5, 1
    blt  x5, x6, cycle

    # One full sweep done: 0+1+...+15 == 120
    li   x29, 120
    bne  x28, x29, fail

    li   x10, 1
    j    report

fail:
    li   x10, 3

report:
    la   t0, tohost
    sw   x10, 0(t0)
    sw   x0, 4(t0)

    # Simulation ends at the tohost write above. On hardware nothing watches
    # tohost, so keep sweeping rather than freezing on a static value -- a
    # board that stays visibly alive is far easier to diagnose than one that
    # stops, since "finished" and "hung" would otherwise look identical. The
    # sticky led[2]/led[3] still record the pass/fail result from that write.
hw_loop:
    sw   x5, 0(x7)
    li   x8, 1
    slli x8, x8, DELAY_SHIFT
hw_delay:
    addi x8, x8, -1
    bne  x8, x0, hw_delay
    addi x5, x5, 1
    andi x5, x5, 15
    j    hw_loop

.section .tohost,"aw",@progbits
.align 6
.global tohost
tohost:   .dword 0
.size tohost, 8

.align 6
.global fromhost
fromhost: .dword 0
.size fromhost, 8
