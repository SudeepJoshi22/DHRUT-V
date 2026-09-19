#include "dhrutv_fpga.h"

int main(void) {
    dhrutv_uart_puts("Hello from a UART-loaded DHRUT-V program!\n");
    dhrutv_uart_puts("Type one character: ");
    char c = (char)dhrutv_uart_getc();
    dhrutv_uart_puts("\nCPU received: ");
    dhrutv_uart_putc(c);
    dhrutv_uart_putc('\n');
    dhrutv_finish(0);
    return 0;
}
