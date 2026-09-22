# Sweep 16 values through LED_ADDR and check their sum (120).
# The low two bits drive led[5:4]; completion is reported through tohost.
# DELAY_SHIFT sets dwell time: default 22 for hardware, use 4 for simulation.

#ifndef DELAY_SHIFT
#define DELAY_SHIFT 22
#endif

.equ LED_ADDR,  0x80007FFC   # top word of the 32 KB dmem; move if DMEM_DEPTH grows
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

    # Continue sweeping LEDs after reporting completion.
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
