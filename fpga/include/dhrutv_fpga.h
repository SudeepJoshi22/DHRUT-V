#ifndef DHRUTV_FPGA_H
#define DHRUTV_FPGA_H

#include <stdint.h>

#define DHRUTV_UART_TXDATA (*(volatile uint32_t *)0x10000000u)
#define DHRUTV_UART_RXDATA (*(volatile uint32_t *)0x10000004u)
#define DHRUTV_UART_STATUS (*(volatile uint32_t *)0x10000008u)
#define DHRUTV_COMPLETION  (*(volatile uint32_t *)0x1000000cu)

static inline uint32_t dhrutv_mcycle(void) {
    uint32_t value;
    __asm__ volatile("csrr %0, mcycle" : "=r"(value));
    return value;
}

static inline void dhrutv_uart_putc(char c) {
    if (c == '\n') dhrutv_uart_putc('\r');
    while (DHRUTV_UART_TXDATA & 0x80000000u) {}
    DHRUTV_UART_TXDATA = (uint8_t)c;
}

static inline void dhrutv_uart_puts(const char *text) {
    while (*text) dhrutv_uart_putc(*text++);
}

static inline int dhrutv_uart_rx_ready(void) {
    return (DHRUTV_UART_STATUS & 2u) != 0;
}

static inline uint8_t dhrutv_uart_getc(void) {
    while (!dhrutv_uart_rx_ready()) {}
    return (uint8_t)DHRUTV_UART_RXDATA;
}

static inline void dhrutv_uart_drain(void) {
    while (DHRUTV_UART_TXDATA & 0x80000000u) {}
}

/* Signal completion to the board LEDs after all output has left the UART.
 * errors=0 encodes the repository's conventional PASS value, 1. */
static inline void dhrutv_finish(uint32_t errors) {
    dhrutv_uart_drain();
    DHRUTV_COMPLETION = (errors << 1) | 1u;
}

#endif
