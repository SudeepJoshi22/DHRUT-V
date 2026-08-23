/* [DHRUT-V] port layer for upstream Dhrystone 2.2 (dhrystone.c/.h,
 * dhrystone_main.c vendored from iammituraj/pequeno_riscv, itself derived
 * from the classic Weicker/Pemberton C sources - see NOTICE).
 *
 * Replaces pqr5's memory-mapped hardware counter + UART ee_printf with:
 *  - mcycle CSR reads for Start_Timer()/Stop_Timer() (see the
 *    DHRUTV_RTLSIM branch added to dhrystone.h).
 *  - no-op ee_printf/uart_init (there's no UART on this core yet; the
 *    self-check dhrystone_main.c does instead reports pass/fail through
 *    the same `tohost` mechanism every other test uses).
 *  - minimal strcpy/strcmp needed by dhrystone.c/dhrystone_main.c,
 *    since we build with -nostdlib (no libc linked).
 */
#include "stats.h"

unsigned int start_cycles   = 0;
unsigned int elapsed_cycles = 0;
unsigned int end_cycles     = 0;

static unsigned int rdcycle(void) {
    unsigned int v;
    __asm__ volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}

void uart_init(void) {
    /* no UART on this core (yet) */
}

int ee_printf(const char *fmt, ...) {
    (void)fmt;
    return 0;
}

void setStats(int enable) {
    if (enable) {
        start_cycles = rdcycle();
    } else {
        end_cycles     = rdcycle();
        elapsed_cycles = end_cycles - start_cycles;
    }
}

char *strcpy(char *dst, const char *src) {
    char *d = dst;
    while ((*d++ = *src++) != '\0') {
    }
    return dst;
}

int strcmp(const char *a, const char *b) {
    while (*a && (*a == *b)) {
        a++;
        b++;
    }
    return (unsigned char)*a - (unsigned char)*b;
}
