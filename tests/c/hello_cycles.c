/* Minimal C bring-up test: computes a known checksum in a loop, then
 * reads mcycle/minstret so a downstream tool (cpu_trace.log) can see
 * the CSR values retire. Returns 0 (pass) iff the checksum matches. */

static unsigned int read_csr_mcycle(void) {
    unsigned int v;
    __asm__ volatile("csrr %0, mcycle" : "=r"(v));
    return v;
}

static unsigned int read_csr_minstret(void) {
    unsigned int v;
    __asm__ volatile("csrr %0, minstret" : "=r"(v));
    return v;
}

int main(void) {
    volatile unsigned int sum = 0;
    for (unsigned int i = 1; i <= 100; i++) {
        sum += i;
    }

    unsigned int cycles = read_csr_mcycle();
    unsigned int instrs = read_csr_minstret();

    /* Keep both live so they show up retiring in cpu_trace.log even
     * though nothing else consumes them (no UART/printf yet). */
    __asm__ volatile("" : : "r"(cycles), "r"(instrs));

    return (sum == 5050) ? 0 : 1;
}
