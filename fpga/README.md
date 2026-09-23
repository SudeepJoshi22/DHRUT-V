# DHRUT-V on the Sipeed Tang Nano 20K

Everything needed to synthesise the CPU, build a bitstream, and run a program on
hardware. Fully open-source flow: **yosys** (with the slang frontend) ->
**nextpnr-himbaechel** -> **gowin_pack** -> **openFPGALoader**.

Target part: **GW2AR-LV18QN88C8/I7** (GW2A-18C family) -- 20,736 LUT4,
15,552 FF, 46 BSRAM blocks, 648 RAM16SDP4 distributed-RAM blocks, 27 MHz
oscillator.

For the shortest fresh-clone board procedure, follow
**[FPGA + UART quick start](QUICKSTART.md)**. The rest of this file explains the
implementation and the lower-level targets.

## First: get the tools

The FPGA toolchain is a separate install from the simulation toolchain, because
it is a ~1.5 GB download most work on this repo does not need:

```bash
./tools/install.sh all                 # from the repo root
```

**Activate one environment at a time.** OSS CAD Suite ships its own Verilator
and Python; if `venv/bin/activate` and `oss-cad-suite/environment` are both on
PATH, the wrong Verilator wins and cocotb runs break in confusing ways. Use the
venv for simulation/upload, and the OSS CAD environment for synthesis and
flashing. The Makefile finds the repository RISC-V compiler while OSS CAD is
active. [QUICKSTART.md](QUICKSTART.md) shows where to switch environments.

## The 60-second version

```bash
# Shell 1: configure the FPGA once
source tools/oss-cad-suite/environment
make -C fpga benchmark-flash BENCH=dhrystone ITERATIONS=1

# Shell 2: select and UART-load programs without re-synthesis
source venv/bin/activate
make -C fpga console PORT=/dev/serial/by-id/<board-port>
```

## How the CPU gets synthesised

### Why there is a wrapper

`cpu_core` **cannot be a synthesis top**. Its ports are SystemVerilog
*interfaces* (`mem_if.master imem_if` / `dmem_if`), and an interface is not
wires until something instantiates it -- there is no parent to do that, and a
`.cst` can only constrain flat scalar ports. Yosys says so directly:

```
top-level module 'cpu_core' has unconnected interface port 'imem_if'
```

`rtl/cpu_top.sv` is that parent. It instantiates the two `mem_if` instances at
the right widths (imem 64-bit -- two instructions per fetch; dmem 32-bit), wires
`cpu_core` onto them, terminates both in on-chip memory, and exposes flat
`clk`, `rst_btn`, `uart_rx`, `uart_tx` and `led[5:0]` ports -- which a `.cst`
*can* constrain.

### The memories

`rtl/bram_slave.sv` replaces the cocotb memory drivers in hardware. It answers
in **one wait state**, because Gowin BSRAM cannot read combinationally, while
honouring the `mem_if` contract: `s_rdata` valid on the same cycle as
`s_ready`, and no answer to a request the master has withdrawn.

Both imem and dmem are writable by the serial loader. Each is split into
byte-wide arrays whose lanes are written whole under their own strobes. Yosys'
Gowin rules have no mapping for a read combined with a byte-masked **partial**
write, so written the obvious way the entire array lands in fabric instead of
BSRAM. Instruction fetch still assembles a 64-bit response from eight lanes;
normal CPU stores use the four dmem lanes.

Neither array has a reset, and both are read and written from a single
`always_ff`. Both are load-bearing for inference: **if it fails, yosys silently
builds flip-flops instead of erroring**, and 16 KB of flip-flops does not fit
anything. Check `stat` for BSRAM primitives rather than trusting a clean exit.

### Baked fallback and serial loading

`$readmemh` is evaluated at **synthesis time** and BSRAM `INIT` is bitstream
data, so the `.fs` file contains a fallback program. The UART loader can replace
that image after configuration without re-synthesis. `fpga/mkmem.py` produces
the fallback images:

```bash
make mem TEST=fpga_blink     # reads ../tests/build/fpga_blink/*.hex + .elf
```

It emits the aggregate `imem_init.hex` / `dmem_init.hex` files plus
`imem_init_b0..b7.hex` and `dmem_init_b0..b3.hex`, the byte-lane images the
writable memories read. It replicates `bram_slave`'s index arithmetic,
NOP-fills imem, and fails loudly on address aliasing. It also prints the
program's real `.tohost` address --
`tests/linker.ld` floats that after `.text`, so it moves per program. If it is
not `0x8000_1000`, pass it through as `TOHOST_ADDR` or the PASS LED can never
light.

Build a test first with `./tools/simulate.sh <name>` from the repo root.
For a hardware-sized program, `BUILD_ONLY=1` skips Spike and the simulator:

```bash
BUILD_ONLY=1 ./tools/simulate.sh fpga_blink      # DELAY_SHIFT=22, ~1 s/LED step
EXTRA_CFLAGS=-DDELAY_SHIFT=4 ./tools/simulate.sh fpga_blink   # simulable
```

### Two synthesis settings that are not defaults

Both are set in the Makefile and both were arrived at by measurement -- see
[AREA_OPTIMIZATION.md](AREA_OPTIMIZATION.md):

**`SYNTH_OPTS = -nowidelut`** -- map to plain LUT4s rather than the
MUX2_LUT5..8 wide-LUT tree. Counter-intuitively this is *smaller* (17,015 ->
14,257 LUT4) and, more importantly, routable: wide LUTs tie groups of LUT4s
into clusters that must be placed adjacently, and that congestion stopped
nextpnr's router converging even at 87% utilisation.

**`FREQ_MHZ = 27`** -- without it nextpnr assumes 12 MHz and reports
"PASS at 12.00 MHz", so timing is never checked against the real oscillator and
the Fmax it prints is an informational by-product rather than a met constraint.

## Make targets

| target | what it does | needs a `.cst`? |
|---|---|---|
| `check` | elaborate + map to Gowin primitives + print `stat`. No PnR. | no |
| `synth` | same, and write `<TOP>.json` (the netlist) | no |
| `bitstream` | synth -> nextpnr -> gowin_pack -> `<TOP>.fs` | yes |
| `flash` | build, then load to **SRAM** (volatile, gone on power cycle) | yes |
| `flash-nv` | build, then write to **onboard flash** (persists) | yes |
| `flash-cpu` | load the existing `cpu_top.fs` to SRAM; no synthesis or PnR | yes |
| `flash-cpu-nv` | write the existing `cpu_top.fs` to onboard flash; no synthesis or PnR | yes |
| `mem` | fallback program -> aggregate and byte-lane memory images | no |
| `area` | per-module LUT/FF ranking + budget verdict | no |
| `clean` | remove `<TOP>`'s `.json` / `.pack.json` / `.fs` | no |
| `clean-all` | remove **everything** generated here -- all tops, all logs, formal work dirs, area baselines (tens of MB) | no |
| `clean-mem` | remove the generated memory images | no |
| `benchmark` | build a Dhrystone/CoreMark hardware ELF | no |
| `benchmark-flash` | bake a fallback, build the CPU bitstream, and configure volatile SRAM | yes |
| `benchmark-flash-nv` | same flow, writing persistent onboard flash | yes |
| `benchmark-upload` | build and UART-load a benchmark without synthesis | no |
| `console` | prompt for benchmark, iterations and validation mode, then upload | no |
| `program-upload` | compile custom C, UART-load it, and attach a terminal | no |
| `elf-upload` | UART-load an existing compatible ELF and attach a terminal | no |
| `terminal` | open a plain 115200-baud serial terminal | no |

### Variables

| variable | default | meaning |
|---|---|---|
| `TOP` | `blink` | top-level module name |
| `FILELIST` | `blink.f` | `.f` list of sources, **order matters** |
| `CST` | `tangnano20k.cst` | pin constraints |
| `TEST` | `add` | which `tests/build/<name>/` to turn into memory images |
| `SYNTH_OPTS` | `-nowidelut` | extra `synth_gowin` flags |
| `FREQ_MHZ` | `27` | nextpnr timing target |
| `PNR_OPTS` | empty | extra nextpnr options, such as `--seed 2 --report timing.json` |
| `AREA_FILELIST` | `cpu_top_filelist.f` | filelist for `make area` only |
| `BENCH` | `dhrystone` | `dhrystone` or `coremark` |
| `ITERATIONS` | `1` | hardware benchmark iteration count |
| `VALIDATION` | `0` | set to `1` for CoreMark validation seeds |
| `PORT` | empty | serial port required by `benchmark-upload` |
| `LOG` | generated benchmark name | UART capture filename |
| `ELF` | empty | arbitrary existing ELF for `elf-upload` |
| `PROGRAM_NAME` | `hello_uart` | output name for a custom C program |
| `PROGRAM_SOURCES` | `examples/hello_uart.c` | custom C source file(s) |

A `.f` file lists one source per line, `#` for **whole-line** comments only --
the Makefile strips `^\s*#` lines but not trailing comments, so a comment after
a filename would be passed to slang as a filename. **Order matters**: packages
and interfaces must precede anything that imports or instantiates them, and the
list must track additions to `rtl/pipeline/` or elaboration fails on an
unresolved instance.

## Commonly used commands

The commands in this section run from the `fpga/` directory (`cd fpga`). The
quick start uses the equivalent `make -C fpga ...` form from the repository
root.

```bash
# Resource check without PnR -- the fast inner loop
make check TOP=cpu_top FILELIST=cpu_top_filelist.f

# Where is the area going? Rank modules, then measure a change against a baseline
make area
make area ARGS="--save base.json"
make area ARGS="--compare base.json"

# Full build and load (SRAM: volatile, good for iterating)
make mem TEST=fpga_blink
make bitstream TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst
make flash     TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst

# Re-load an already-built CPU bitstream without rebuilding it
make flash-cpu

# Make it survive a power cycle
make flash-nv TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst

# Build and upload a benchmark through the FPGA UART loader
make benchmark-upload BENCH=dhrystone ITERATIONS=50000 \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE LOG=dhrystone-50000.log

# Interactive benchmark/iteration selection
make console PORT=/dev/serial/by-id/ACTUAL_DEVICE

# Compile, upload and interact with a custom bare-metal C program
make program-upload PROGRAM_NAME=my_app PROGRAM_SOURCES=../my_app.c \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE

# Or upload any compatible ELF you built elsewhere
make elf-upload ELF=/path/to/program.elf \
  PORT=/dev/serial/by-id/ACTUAL_DEVICE

# Bake a benchmark into a new SRAM or persistent bitstream
make benchmark-flash BENCH=dhrystone ITERATIONS=1
make benchmark-flash-nv BENCH=coremark ITERATIONS=1000

# Targeted UART, loader and host-protocol verification
make verify-uart
make verify-loader BENCH=dhrystone ITERATIONS=1
make verify-host
make verify-mem
make verify-bram BRAM_TEST=dhrystone_edgefix EXPECTED_CYCLES=759

# Sanity-check the toolchain on something trivial before blaming the CPU
make bitstream TOP=blink FILELIST=blink.f CST=tangnano20k.cst

# Reclaim disk: logs and bitstreams add up fast (43 MB after one session).
# Lists what it removes; sources are never touched.
make clean-all

# NOTE: you cannot elaborate cpu_core on its own -- `make check TOP=cpu_core
# FILELIST=cpu_filelist.f` fails with "unconnected interface port 'imem_if'",
# which is the whole reason cpu_top exists. cpu_filelist.f is the source list
# cpu_top_filelist.f is built from, not a usable target by itself.

# Equivalence proofs for the optimised datapaths
cd formal && sby -f alu_equiv.sby --yosys "yosys -m slang"
```

Save the log when you care about the result --
`make check ... 2>&1 | tee check.log`. Reconstructing a synthesis result from a
168 MB netlist because no log was kept is not fun.

## Stage 2 hardware benchmarking progress

Instruction and data memory defaults are now **32 KB each**. `mkmem.py` checks
the image against both capacities and checks ELF `_ebss`, `_end` and
`_stack_top` when present. It rejects a lone out-of-range address even when no
second address collides with its wrapped index. `make mem` changes now
invalidate the synthesized CPU netlist.

The CPU dmem bus splits RAM and MMIO requests. The UART occupies `0x1000_0000`
through `0x1000_0008`, and software reports completion at `0x1000_000c`. The
hardware loader holds the CPU in reset, accepts a checked binary into both
memories, and then starts the CPU. A 500 ms timeout runs the baked fallback
image; a partial or invalid upload cannot execute.

The one-iteration Dhrystone and CoreMark images fit, with stack tops
`0x80007040` and `0x80005840` respectively. With the CoreMark image, integrated
Gowin synthesis (`-nowidelut`, 2026-09-19) uses:

| Resource | Used | Device capacity |
|---|---:|---:|
| LUT4 | 17,054 | 20,736 |
| ALU | 1,472 | 15,552 |
| FF | 3,929 | 15,552 |
| RAM16SDP4 | 17 | 648 |
| BSRAM | 32 | 46 |

The fully routed build reaches **28.33 MHz Fmax and passes the 27 MHz board
constraint**. The placer estimate was only 25.75 MHz; the final routed timing
report is authoritative. Do not flash a build whose final report says
`FAIL at 27.00 MHz`.

Fast checks from the repository root, with the usual venv/toolchain active:

```bash
make -C fpga verify-mem
make -C fpga verify-bram BRAM_TEST=dhrystone_edgefix EXPECTED_CYCLES=759
make -C fpga verify-bram BRAM_TEST=coremark_edgefix EXPECTED_CYCLES=383043
make -C fpga verify-uart
make -C fpga verify-loader BENCH=dhrystone ITERATIONS=1
make -C fpga verify-loader BENCH=coremark ITERATIONS=1 EXPECTED_ERRORS=1
make -C fpga verify-host
```

The BRAM check consumes an existing `tests/build/<name>/<name>.elf`/`.hex`
pair, sets `TOHOST_ADDR` from the ELF, and runs the actual `cpu_top` wrapper.
It checks the completion LEDs and timed-result writes, using isolated build
directories. Both benchmarks pass and match the fixed-mode Python model's
cycle counts exactly. Native simulation avoids the expensive Python CPU
tracing; it is still simulation, not evidence from a physical board.

The integrated UART uses 115200 baud, 8N1, with no flow control. On reset it
sends `R`; `loadprog.py` then sends a `DHRV` header, payload length, binary and
additive checksum. `K` accepts the image and starts the CPU; `E` rejects it.
The same open serial connection prints benchmark output and a final
`DHRUTV_RESULT` line, which the host tool saves as JSON. The exact protocol,
terminal setup and recovery behavior are in [UART_PLAN.md](UART_PLAN.md).

## Reading the board

Six LEDs, active-low, allocated 1+1+2+2 so they answer four different questions:

| LED | meaning |
|---|---|
| `[0]` | **heartbeat** -- free-running counter off the raw clock, independent of the core. Distinguishes "bad bitstream" from "stuck core". |
| `[1]` | **fetch activity** -- advances on every completed fetch. Blinks while running, **freezes on a hang**. No sticky flag can show this. |
| `[2]` | `tohost` written (program finished) |
| `[3]` | `tohost == 1` (program passed) |
| `[5:4]` | **driven by software** -- a store to `LED_ADDR` (`0x8000_7ffc` for 32 KB dmem) latches its low 2 bits |

The software LEDs remain a snoop on the RAM write bus. The completion register
and UART are selected by `dmem_splitter`; RAM addresses continue to the BSRAM
slave.

Diagnosing a dark board:

| symptom | meaning |
|---|---|
| no heartbeat | bitstream, clock or pin problem -- the core is not implicated |
| heartbeat only | core never fetched: reset stuck, or imem empty |
| fetch activity freezes | core hung, most likely a stalled `mem_if` handshake |
| fetching but no software LEDs | executing, but stores are wrong or `LED_ADDR` mismatches |

## Files here

| | |
|---|---|
| `rtl/cpu_top.sv` | synthesis top: CPU, memories, loader, UART and LED panel |
| `rtl/bram_slave.sv` | `mem_if` slave backed by BSRAM |
| `rtl/dmem_splitter.sv` | CPU data-bus RAM/MMIO decoder |
| `rtl/prog_loader.sv` | checked UART-to-memory program loader |
| `cpu_top_filelist.f` | sources for the full CPU build |
| `cpu_filelist.f` | CPU sources without the FPGA wrapper (not a synthesis target -- see above) |
| `cpu_top.cst` | pin constraints for `cpu_top` |
| `tangnano20k.cst` | pin constraints for the `blink` smoke test |
| `blink.f` / `blink.v` | CPU-less LED blinker, for proving the board and flow |
| `mkmem.py` | program image generator |
| `build_benchmark.py` | internal helper that builds a hardware benchmark ELF |
| `loadprog.py` | internal serial upload, result capture and interactive terminal helper |
| `include/dhrutv_fpga.h` | public UART, cycle counter and completion API |
| `examples/hello_uart.c` | minimal interactive custom program |
| `CUSTOM_PROGRAMS.md` | build and memory-map guide for user programs |
| `area_report.py` | per-module area report (`make area`) |
| `formal/` | SymbiYosys equivalence proofs for the ALU and LSU rewrites |
| `AREA_OPTIMIZATION.md` | how the design was made to fit, including what failed |
| `UART_PLAN.md` | implemented UART/loader protocol and operator guide |

## Known rough edges

- **The auxiliary LED pins in `cpu_top.cst` remain unverified.** `led[1..5]`
  were extrapolated from a known-good `led0 = 15`. The reset button and UART
  path have been exercised on the board; UART TX/RX use documented pins 69/70.
  Wrong auxiliary LED pins show up as dark LEDs, not as a build error.
- **The serial hardware path has passed board bringup and benchmark execution.**
  The loader greeting, baked Dhrystone fallback, UART-loaded `hello_uart`, and
  CoreMark performance and validation runs all ran over the onboard USB bridge.
  The remaining benchmark work is the full Dhrystone sweep and the
  simulation-to-hardware cycle comparison.
