# FPGA resources and synthesis

The Tang Nano 20K configuration contains the RV32IM_Zicsr CPU, 32 KB of
instruction RAM, 32 KB of data RAM, UART and a serial program loader.

## Resource and timing report

The recorded integrated CoreMark-image synthesis uses `-nowidelut`:

| Resource | Used | Capacity |
|---|---:|---:|
| LUT4 | 17,054 | 20,736 |
| ALU | 1,472 | 15,552 |
| FF | 3,929 | 15,552 |
| RAM16SDP4 | 17 | 648 |
| BSRAM | 32 | 46 |

The routed build reaches 28.33 MHz Fmax and meets the 27 MHz board constraint.
Resource use depends on the baked program and build settings. Use the final
place-and-route report to assess a specific bitstream.

## Storage and datapaths

- **BPU:** 16 entries, 10-bit tags and two-bit prediction counters. An unpacked
  array with initialization and a single write port maps into distributed RAM.
  Resolved branch updates take priority over speculative allocations.
- **Fetch queue:** eight entries with two push and two pop ports.
- **RAS:** eight return-address entries.
- **Register file:** 32 registers with four read ports and two write ports.
  Operand selection and forwarding contribute to mux and routing cost.
- **Instruction and data RAM:** byte-lane arrays provide synchronous reads and
  byte writes for CPU stores and program loading. Memory arrays have no reset.
- **ALU and LSU:** shared arithmetic and shift logic implements the datapaths.
  Equivalence checks are available under `formal/`.
- **Scoreboard:** per-register outstanding-write counters track pending results.
  Consumers of an outstanding MDU result wait for writeback.
- **MDU:** a multiplier mapped to DSP hardware and a restoring divider.

## Build settings

`SYNTH_OPTS=-nowidelut` maps logic without the wide-LUT mux structures.
`FREQ_MHZ=27` sets the place-and-route clock constraint.

The netlist depends on the RTL sources, filelist and memory initialization
images. Changing baked program contents requires rebuilding the bitstream.
UART program uploads update BRAM at runtime.

Timing headroom is limited: the recorded routed Fmax is 28.33 MHz against a
27 MHz target. Changes to operand muxes, forwarding, arithmetic or storage
require a new timing report.

## Measuring

Run from `fpga/` with OSS CAD Suite active:

```bash
make area
make area ARGS="--save base.json"
make area ARGS="--compare base.json"
make bitstream TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst
```

The area tool runs complete synthesis. The flat report gives the mapped total;
the hierarchy-preserving report attributes cost to modules. Hierarchical totals
can differ because preserving module boundaries limits cross-module
optimization. Final packing, routing and timing determine whether a build fits.

ALU cells have a separate device budget. Dedicated wide-LUT mux cells do not
add to the LUT4 total; their constituent LUT4s are already counted.

See [README.md](README.md) for build commands and the memory map, and
[QUICKSTART.md](QUICKSTART.md) for board operation.
