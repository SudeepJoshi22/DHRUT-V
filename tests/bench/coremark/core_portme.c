/*
Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)
Licensed under the Apache License, Version 2.0 - see NOTICE.md.
Original Author: Shay Gal-on

[DHRUT-V]: port for the DHRUT-V RISC-V core. Timing comes from the
mcycle CSR instead of a memory-mapped counter; there's no UART, so
ee_printf is a no-op and results are read back from the
dhrutv_final_* globals (see core_main.c) instead of printed text.
*/
#include "coremark.h"
#include "core_portme.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

#ifndef DHRUTV_ASSUMED_MHZ
#define DHRUTV_ASSUMED_MHZ 100 /* only used to normalize the CoreMark/MHz score */
#endif

long dhrutv_final_iterations   = 0;
long dhrutv_final_total_cycles = 0;
long dhrutv_final_mhz          = DHRUTV_ASSUMED_MHZ;

static unsigned int rdcycle(void) {
    unsigned int v;
    __asm__ volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}

CORETIMETYPE barebones_clock(void) {
    return (CORETIMETYPE)rdcycle();
}

#define GETMYTIME(_t)              (*_t = barebones_clock())
#define MYTIMEDIFF(fin, ini)       ((fin) - (ini))
#define TIMER_RES_DIVIDER          1
#define SAMPLE_TIME_IMPLEMENTATION 1
#define EE_TICKS_PER_SEC           (CLOCKS_PER_SEC / TIMER_RES_DIVIDER)

static CORETIMETYPE start_time_val, stop_time_val;

void start_time(void) {
    GETMYTIME(&start_time_val);
}

void stop_time(void) {
    GETMYTIME(&stop_time_val);
}

CORE_TICKS get_time(void) {
    CORE_TICKS elapsed = (CORE_TICKS)(MYTIMEDIFF(stop_time_val, start_time_val));
    return elapsed;
}

secs_ret time_in_secs(CORE_TICKS ticks) {
    secs_ret retval = ((secs_ret)ticks) / (secs_ret)EE_TICKS_PER_SEC;
    return retval;
}

ee_u32 default_num_contexts = 1;

int ee_printf(const char *fmt, ...) {
    (void)fmt;
    return 0;
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    p->portable_id = 1;
}

void portable_fini(core_portable *p) {
    p->portable_id = 0;
}
