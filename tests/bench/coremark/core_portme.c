/*
Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)
Licensed under the Apache License, Version 2.0 - see NOTICE.md.
Original Author: Shay Gal-on

[DHRUT-V]: port for the DHRUT-V RISC-V core. Timing comes from the
mcycle CSR instead of a memory-mapped counter. ee_printf observes validation
messages and optionally prints via UART for hardware builds. Simulation
recovers the dhrutv_final_* globals.
*/
#include "coremark.h"
#include "core_portme.h"
#ifdef DHRUTV_UART
#include "core_portme_uart.h"
#endif

#if !defined(ITERATIONS) || ITERATIONS <= 0
#error "DHRUT-V result capture requires an explicit positive ITERATIONS"
#endif
#if MULTITHREAD != 1
#error "DHRUT-V currently supports one CoreMark context"
#endif

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

long dhrutv_final_errors       = 0;
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

static int validated;

static int starts_with(const char *text, const char *prefix) {
    while (*prefix) {
        if (*text++ != *prefix++) return 0;
    }
    return 1;
}

/* Observe the unmodified benchmark's verdict, not its unconditional return
   value. CRC messages begin with "[%u]ERROR!", datatype/time errors with
   "ERROR", and unknown seeds produce "Cannot validate". Require the explicit
   success message as well, so an unrecognized/incomplete run cannot pass. */
int ee_printf(const char *fmt, ...) {
    if (!fmt) return 0;
#ifdef DHRUTV_UART
    va_list args;
    va_start(args, fmt);
    uart_vprintf(fmt, args);
    va_end(args);
    uart_drain();
#endif
    if (starts_with(fmt, "Correct operation validated.")) validated = 1;
    if (starts_with(fmt, "Errors detected") || starts_with(fmt, "Cannot validate")) {
        dhrutv_final_errors = 1;
    }
    for (const char *s = fmt; *s; ++s) {
        if (starts_with(s, "ERROR")) dhrutv_final_errors = 1;
    }
    return 0;
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    validated = 0;
    dhrutv_final_errors = 0;
    p->portable_id = 1;
}

/* Report once and halt: returning to crt0 would overwrite a failing verdict
   with main's unconditional zero return before Spike polls tohost.
   Convention: bit0 = done, bits[31:1] = exit code, 0 = pass. */
extern volatile unsigned long long tohost;

void portable_fini(core_portable *p) {
    p->portable_id = 0;

    /* Score, for tools/bench_report.py to recover from the dmem write trace.
       Cycles come from the timestamps this file already keeps; iterations
       from the compile-time ITERATIONS, since results[].iterations lives in
       core_main.c's scope. Auto-calibration (ITERATIONS unset) is therefore
       not reportable -- always pass -DITERATIONS=<n>. */
    dhrutv_final_iterations = (long)((ee_u32)default_num_contexts * (ee_u32)ITERATIONS);
    dhrutv_final_total_cycles =
        (long)(CORE_TICKS)(stop_time_val - start_time_val);

    if (!validated) dhrutv_final_errors = 1;
#ifdef DHRUTV_UART
    uart_printf("DHRUTV_RESULT coremark iterations=%lu cycles=%lu clock_hz=%lu errors=%lu\n",
                (unsigned long)dhrutv_final_iterations,
                (unsigned long)dhrutv_final_total_cycles,
                (unsigned long)DHRUTV_CLOCK_HZ, (unsigned long)dhrutv_final_errors);
    *(volatile unsigned *)0x1000000cu = ((unsigned)dhrutv_final_errors << 1) | 1u;
#endif
    __asm__ volatile("" ::: "memory");
    tohost = ((unsigned long long)dhrutv_final_errors << 1) | 1ULL;
    for (;;) __asm__ volatile("nop");
}
