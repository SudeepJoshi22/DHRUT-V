# Custom programs on the FPGA CPU

The FPGA bitstream contains the DHRUT-V CPU, UART, hardware program loader and
32 KB instruction/data memories. Flash that hardware once. A custom application
is then an ordinary RV32IM bare-metal ELF uploaded into BRAM over UART; changing
the application does not run synthesis or reconfigure the FPGA.

Complete the configuration and serial-port steps in
[QUICKSTART.md](QUICKSTART.md), then activate `venv/bin/activate` before the
commands below.

## Smallest example

```c
#include "dhrutv_fpga.h"

int main(void) {
    dhrutv_uart_puts("Hello from my program!\n");
    dhrutv_uart_puts("Press a key: ");
    char c = dhrutv_uart_getc();
    dhrutv_uart_puts("\nReceived: ");
    dhrutv_uart_putc(c);
    dhrutv_uart_putc('\n');
    dhrutv_finish(0);
    return 0;
}
```

Save this as `my_app.c`, then compile, upload and attach the terminal with:

```bash
make -C fpga program-upload \
  PROGRAM_NAME=my_app \
  PROGRAM_SOURCES=../my_app.c \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE
```

Press and release reset when prompted. Quit the interactive terminal with
Ctrl-]. Multiple files and extra compiler definitions are supported:

```bash
make -C fpga program-upload \
  PROGRAM_NAME=my_app \
  PROGRAM_SOURCES="../my_app.c ../driver.c" \
  PROGRAM_CFLAGS="-DMODE=2" \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE
```

The output ELF is `tests/build/my_app/my_app.elf`. The default example can be
run with only:

```bash
make -C fpga program-upload PORT=/dev/serial/by-id/ACTUAL_DEVICE
```

## Upload an ELF built elsewhere

```bash
make -C fpga elf-upload ELF=/path/to/program.elf \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE
```

The ELF must use the repository's bare-metal layout:

- RV32IM with Zicsr, ILP32 ABI.
- Entry point `_start` at `0x80000000`.
- Initialized image and code fit in 32 KB.
- Data, BSS and stack fit in the separate 32 KB data memory.
- No operating system or standard C library is present.

`program-build` supplies `tests/crt0.S`, `tests/linker_c.ld`, `libgcc`, and the
required compiler flags automatically. `elf-upload` validates the address and
memory bounds before opening the serial port.

## Software interface

Include `fpga/include/dhrutv_fpga.h` through the Make target's default include
path. It provides:

- `dhrutv_uart_putc`, `dhrutv_uart_puts`: blocking UART output.
- `dhrutv_uart_getc`, `dhrutv_uart_rx_ready`: UART input.
- `dhrutv_mcycle`: the CPU cycle counter.
- `dhrutv_finish(errors)`: drain output and signal completion/pass to the LEDs.

The underlying MMIO addresses are:

| Address | Function |
|---|---|
| `0x10000000` | UART TX data/busy |
| `0x10000004` | UART RX data/empty |
| `0x10000008` | UART status |
| `0x1000000c` | completion value `(errors << 1) | 1` |

## What persists

- Pressing reset re-enters the loader. After a successful upload, the uploaded
  image remains in BRAM across button resets until another upload.
- Power cycling or reconfiguring the FPGA restores the program baked into the
  bitstream.
- `benchmark-upload`, `program-upload`, and `elf-upload` change BRAM only.
- `benchmark-flash` and `benchmark-flash-nv` rebuild and configure the FPGA.
