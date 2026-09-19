# UART and serial program loading

Stage 2 implementation: 32 KB instruction RAM + 32 KB data RAM, UART MMIO,
hardware loader, benchmark printing, and laptop upload/capture. Board validation
and iteration sweeps remain separate from simulation results.

## How output reaches the laptop

```
benchmark port -> UART MMIO -> FPGA TX pin 69 -> onboard BL616 -> USB -> laptop
```

RX is pin 70. Both pins use LVCMOS33. The bridge and pin assignment follow
[Sipeed's example](https://github.com/sipeed/TangNano-20K-example/blob/e23949a0a77381b94960cbc4e97a7c5e5ba8d222/uart/src/top.cst).
The onboard bridge provides USB serial without an external adapter. Its default
FPGA communication mode is UART; the bridge console's `choose uart` restores
that mode if changed. See [Sipeed's board guide](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/example/unbox.html).

Use **115200 baud, 8 data bits, no parity, one stop bit, no flow control**.
The FPGA uses 27 MHz / 234 = 115384.6 baud (0.16% error). Discover the actual
Linux device under `/dev/serial/by-id/` or with `python3 -m serial.tools.list_ports`;
it may be ttyUSB or ttyACM. Windows uses a COM port. Only one application should
open the port at a time.

## Build and run

Commands below run from the repository root. Put the RISC-V GCC toolchain,
Verilator and OSS CAD Suite on PATH. Host upload requires Python's `pyserial`.
The Makefile is the operator interface; its Python helpers implement ELF
construction and the wire protocol without launching the slow pyUVM simulation.

```bash
make -C fpga benchmark-flash BENCH=dhrystone ITERATIONS=1
```

This SRAM flash lasts until power-off. `flash-nv` writes persistent flash.
To see the baked-in benchmark, open a serial terminal at the settings above,
then press and release reset. An initial `R` is the loader greeting; without
an upload, the program starts after 500 ms. Opening the terminal before reset
prevents losing a short benchmark's output.

Once this hardware is installed, new programs need no synthesis:

```bash
make -C fpga benchmark-upload BENCH=dhrystone ITERATIONS=50000 \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE LOG=dhrystone-50000.log
```

The tool opens the port and asks you to press and release the FPGA reset button.
It waits for `R`, uploads, checks `K`, then **keeps the same connection open** to
print and save output. An adjacent acknowledgment and first text byte are not
lost. It saves a JSON result beside the log, including ELF hash and available
build metadata. Errors or a missing final result cause a nonzero host exit.

For CoreMark, build `coremark --iterations N`, optionally `--validation` for the
validation seeds. Hardware builds enforce the real 27 MHz timebase: a one-iteration
CoreMark run is expected to fail its ten-second rule even when all CRCs pass.
Increase iterations until the actual timed interval is at least ten seconds.
Both required seed sets must pass before publishing a rule-valid result.
These remain self-measured results, not EEMBC-certified scores.

## Software interface

| Address | Behavior |
|---|---|
| `0x80000000` + | RAM; existing high-bit aliases retained |
| `0x10000000` | TXDATA: write byte in lane 0; read bit 31 = busy |
| `0x10000004` | RXDATA: read pops byte; bit 31 = empty |
| `0x10000008` | STATUS: bit 0 busy, bit 1 RX valid, bit 2 overrun; write-one-clear bit 2 |
| `0x1000000c` | Completion LED snoop: write `(errors << 1) | 1`; reads zero |

Other low addresses respond with zero rather than hanging the CPU. A busy TX
write waits for capacity. UART has an eight-byte RX FIFO. The original RAM LED
snoop remains at `0x80007ffc`. The completion MMIO address avoids changing the
bitstream when an uploaded ELF places `tohost` at a different address.

Both benchmark ports print a final machine-readable line:

```
DHRUTV_RESULT dhrystone iterations=50000 cycles=... clock_hz=27000000 errors=0
```

All serial printing is outside the measured interval. Output drains before
completion is signaled. CoreMark's protected algorithm sources are unchanged;
UART support is in `core_portme*`. The formatter supports the integer/string
formats used with `HAS_FLOAT=0`; it is not a general libc printf.
The host derives `iterations * 1e6 / cycles`, divided by 1757 for DMIPS/MHz.
The current timer is 32-bit: keep each timed interval below 2^32 cycles
(about 159 seconds at 27 MHz). Do not interpret a wrapped interval as a score.

## Loader contract and recovery

On reset the CPU is held stopped while the loader owns UART and both RAM ports.
It transmits `R`, then waits 500 ms for this frame:

```
DHRV | LE32 payload_length | payload | LE32 sum(payload)
```

The ELF must start at `0x80000000`. The host checks initialized data, BSS and
stack against the 32 KB memories, reserving the last data word for LEDs. Holes
in the transmitted image are zero-filled. Payload bytes are written identically
into both memories through multiplexed single ports. CPU writes to IMEM remain
unsupported. The checksum detects accidental transfer errors; it is not authentication.

Length must be 1..32764 bytes. `K` means accepted; the CPU starts only after the
acknowledgment's stop bit. `E` means rejection. After a recognized header,
one second without a byte also rejects the transfer. Failure holds the CPU
stopped until reset. A partial overwrite invalidates memory **across button
resets**, so a later timeout cannot execute a corrupt image. Upload a complete
replacement or reconfigure the FPGA to recover. A successful upload makes that
image the fallback on subsequent resets; reset does not restore baked RAM.

## Verification

- `make -C fpga verify-uart`: standalone UART framing, FIFO and MMIO.
- `make -C fpga verify-host`: host transfer/capture over a pseudo-terminal,
  including ACK immediately followed by output, rejection and missing greeting.
- `make -C fpga verify-loader BENCH=dhrystone ITERATIONS=1`: real CPU, UART and writable BRAM; baked fallback,
  invalid lengths, interrupted payload, checksum failure, reset recovery and
  successful serial-loaded benchmark output.
- `make -C fpga verify-loader BENCH=coremark ITERATIONS=1 EXPECTED_ERRORS=1`: CoreMark UART reporting with
  its expected short-run time-gate failure preserved as `errors=1`.
- `make -C fpga verify-bram BRAM_TEST=TEST`: targeted existing CPU tests using the RAM/bus
  wrapper, with loading disabled for speed.

Board acceptance still requires actual USB capture, iteration convergence,
CoreMark duration/validation, and a hardware/simulation cycle cross-check.
