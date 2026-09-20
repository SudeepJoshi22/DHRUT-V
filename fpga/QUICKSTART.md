# FPGA + UART quick start

This is the linear, fresh-clone procedure for a Sipeed Tang Nano 20K. Run all
commands from the repository root unless a command says otherwise.

## 1. Install the two tool sets

```bash
./tools/install.sh all
```

This installs the repository RISC-V cross compiler and Python environment plus
OSS CAD Suite. The Makefile locates the repository compiler automatically, so
do not activate the simulation venv while synthesizing.

## 2. Configure the FPGA once

Connect the board over USB, then start a clean shell:

```bash
source tools/oss-cad-suite/environment
make -C fpga benchmark-flash BENCH=dhrystone ITERATIONS=1
deactivate
```

This builds firmware, synthesizes and routes the CPU/UART/loader, checks the
27 MHz constraint, creates `fpga/cpu_top.fs`, and loads it into FPGA SRAM.
Expect the first build to take several minutes. SRAM configuration disappears
at power-off; use `benchmark-flash-nv` instead if the configuration should
survive power cycling.

The one-iteration Dhrystone image is only the baked recovery program. Once the
bitstream is installed, changing CPU software does not repeat synthesis.

## 3. Find the USB UART

Start a new shell with the repository Python environment:

```bash
source venv/bin/activate
python3 -m serial.tools.list_ports -v
ls -l /dev/serial/by-id/ 2>/dev/null
```

Prefer the stable `/dev/serial/by-id/...` name. A `/dev/ttyUSB*` or
`/dev/ttyACM*` name also works. If opening it reports permission denied, add
your account to `dialout`, then log out and back in:

```bash
sudo usermod -aG dialout "$USER"
# Then log out and back in, or start a new shell immediately:
newgrp dialout
```

UART is 115200 baud, 8 data bits, no parity, one stop bit, no flow control.
Only one terminal/uploader may have the port open. If no serial port appears,
check the USB cable and restore the onboard BL616 bridge to UART mode with its
`choose uart` command.

## 4. Prove bidirectional UART with the example

```bash
make -C fpga program-upload \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE
```

The tool asks you to press and release reset. The hardware loader then receives
the example ELF and the terminal remains connected. Expected interaction:

```text
Hello from a UART-loaded DHRUT-V program!
Type one character: x
CPU received: x
```

Quit the interactive terminal with Ctrl-]. This single test proves reset,
laptop-to-FPGA RX, checked program loading, CPU execution, and FPGA-to-laptop
TX.

## 5. Select and run a benchmark

```bash
make -C fpga console PORT=/dev/serial/by-id/ACTUAL_DEVICE
```

Choose `dhrystone` or `coremark`, enter the iteration count, and press/release
reset when asked. The selected benchmark is compiled and uploaded into BRAM;
the FPGA bitstream is not rebuilt. Benchmark output appears in the same shell.

A direct reproducible run is:

```bash
make -C fpga benchmark-upload \
  BENCH=dhrystone ITERATIONS=50000 \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE \
  LOG=dhrystone-50000.log
```

Success ends with a line shaped like:

```text
DHRUTV_RESULT dhrystone iterations=50000 cycles=... clock_hz=27000000 errors=0
```

The tool writes the UART transcript and an adjacent JSON result. For a
CoreMark result that satisfies its duration check, start with 1000 iterations
and confirm the reported duration is at least ten seconds:

```bash
make -C fpga benchmark-upload \
  BENCH=coremark ITERATIONS=1000 \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE \
  LOG=coremark-1000.log
```

## 6. Load your own program

Follow [CUSTOM_PROGRAMS.md](CUSTOM_PROGRAMS.md). The shortest form compiles the
provided example; replace `PROGRAM_SOURCES` with your own C file:

```bash
make -C fpga program-upload \
  PROGRAM_NAME=my_app PROGRAM_SOURCES=../my_app.c \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE
```

An existing compatible ELF can be uploaded with `make -C fpga elf-upload`.

## Recovery

- No loader greeting: close other serial programs, verify the port, then press
  and release reset.
- Upload rejected with `E`: reset and retry; check that the ELF starts at
  `0x80000000` and fits the 32 KB memories.
- Transfer interrupted: reset and upload a complete image. A partial image is
  deliberately never executed.
- Corrupt BRAM or repeated failure: reconfigure the FPGA to restore the baked
  fallback image.
- No heartbeat LED after configuration: investigate bitstream, clock, USB/JTAG
  and pin assignment before debugging software.

Physical-board UART acceptance is still pending in the repository record, so
retain the first successful logs and JSON files as the hardware evidence.
