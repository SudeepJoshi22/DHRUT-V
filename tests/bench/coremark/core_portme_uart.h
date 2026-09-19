/* DHRUT-V freestanding UART output. Included only by hardware port builds.
 * Integer/string formatting covers the HAS_FLOAT=0 benchmark reports. */
#ifndef DHRUTV_UART_PORT_H
#define DHRUTV_UART_PORT_H
#include <stdarg.h>
#ifndef DHRUTV_CLOCK_HZ
#define DHRUTV_CLOCK_HZ 27000000u
#endif
static void uart_drain(void) {
    while (*(volatile unsigned *)0x10000000u & 0x80000000u) {}
}
static void uart_putc(char c) {
    if (c == '\n') uart_putc('\r');
    uart_drain();
    *(volatile unsigned *)0x10000000u = (unsigned char)c;
}
static void uart_number(unsigned long value, unsigned base, int width, char pad) {
    char digits[32];
    int n = 0;
    do { digits[n++] = "0123456789abcdef"[value % base]; value /= base; } while (value);
    while (width-- > n) uart_putc(pad);
    while (n) uart_putc(digits[--n]);
}
static void uart_vprintf(const char *fmt, va_list args) {
    while (*fmt) {
        if (*fmt++ != '%') { uart_putc(fmt[-1]); continue; }
        char pad = ' ';
        int width = 0, is_long = 0;
        if (*fmt == '0') { pad = '0'; ++fmt; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + *fmt++ - '0';
        if (*fmt == 'l') { is_long = 1; ++fmt; }
        char spec = *fmt;
        if (!spec) break;
        ++fmt;
        if (spec == 's') {
            const char *s = va_arg(args, const char *);
            if (!s) s = "(null)";
            while (*s) uart_putc(*s++);
        } else if (spec == 'c') uart_putc((char)va_arg(args, int));
        else if (spec == '%') uart_putc('%');
        else if (spec == 'd' || spec == 'i') {
            long v = is_long ? va_arg(args, long) : va_arg(args, int);
            unsigned long magnitude = (unsigned long)v;
            if (v < 0) { uart_putc('-'); magnitude = 0ul - magnitude; --width; }
            uart_number(magnitude, 10, width, pad);
        } else if (spec == 'u' || spec == 'x' || spec == 'X') {
            unsigned long v = is_long ? va_arg(args, unsigned long) : va_arg(args, unsigned);
            uart_number(v, spec == 'u' ? 10 : 16, width, pad);
        } else if (spec == 'p') {
            uart_number((unsigned long)va_arg(args, void *), 16, width, pad);
        } else { uart_putc('%'); uart_putc(spec); }
    }
}
static void uart_printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    uart_vprintf(fmt, args);
    va_end(args);
    uart_drain();
}
#endif
