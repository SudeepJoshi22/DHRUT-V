# DHRUT-V on the Sipeed Tang Nano 20K

Everything needed to synthesise the CPU, build a bitstream, and run a program on
hardware. Fully open-source flow: **yosys** (with the slang frontend) ->
**nextpnr-himbaechel** -> **gowin_pack** -> **openFPGALoader**.

Target part: **GW2AR-LV18QN88C8/I7** (GW2A-18C family) -- 20,736 LUT4,
15,552 FF, 46 BSRAM blocks, 648 RAM16SDP4 distributed-RAM blocks, 27 MHz
oscillator.

## First: get the tools

The FPGA toolchain is a separate install from the simulation toolchain, because
it is a ~1.5 GB download most work on this repo does not need:

```bash
./tools/install.sh fpga-tools          # from the repo root
source tools/oss-cad-suite/environment
```

**Activate one environment at a time.** OSS CAD Suite ships its own Verilator
and Python; if `venv/bin/activate` and `oss-cad-suite/environment` are both on
PATH, the wrong Verilator wins and cocotb runs break in confusing ways. Use the
venv for simulation, the OSS CAD environment for everything in this directory.

## The 60-second version

```bash
cd fpga
make mem TEST=fpga_blink                                        # program -> memory images
make bitstream TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst
make flash     TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst
```

`make mem` must come first -- see *The program lives in the bitstream* below.

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
`cpu_core` onto them, terminates both in on-chip memory, and exposes only
`clk`, `rst_n_btn` and `led[5:0]` -- which a `.cst` *can* constrain.

### The memories

`rtl/bram_slave.sv` replaces the cocotb memory drivers in hardware. It answers
in **one wait state**, because Gowin BSRAM cannot read combinationally, while
honouring the `mem_if` contract: `s_rdata` valid on the same cycle as
`s_ready`, and no answer to a request the master has withdrawn.

It has two shapes, and the difference matters:

- **ROM path** (imem, `WRITABLE=0`) -- one array. The write branch folds away
  and it infers as BSRAM cleanly.
- **RAM path** (dmem, `WRITABLE=1`) -- split into byte-wide arrays, each
  written *whole* under its own strobe. Yosys' Gowin rules have no mapping for
  a read combined with a byte-masked **partial** write, so written the obvious
  way the entire array lands in fabric instead of BSRAM.

Neither array has a reset, and both are read and written from a single
`always_ff`. Both are load-bearing for inference: **if it fails, yosys silently
builds flip-flops instead of erroring**, and 16 KB of flip-flops does not fit
anything. Check `stat` for BSRAM primitives rather than trusting a clean exit.

### The program lives in the bitstream

`$readmemh` is evaluated at **synthesis time** and BSRAM `INIT` is bitstream
data, so the program is baked into the `.fs` file. Changing the program means a
full re-synthesis. `fpga/mkmem.py` produces the images:

```bash
make mem TEST=fpga_blink     # reads ../tests/build/fpga_blink/*.hex + .elf
```

It emits `imem_init.hex` (64-bit/line), `dmem_init.hex` (32-bit/line) and
`dmem_init_b0..b3.hex` (the per-byte-lane images the RAM path reads), replicates
`bram_slave`'s index arithmetic, NOP-fills imem, and fails loudly on address
aliasing. It also prints the program's real `.tohost` address --
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
| `mem` | program image -> `imem_init.hex` / `dmem_init*.hex` | no |
| `area` | per-module LUT/FF ranking + budget verdict | no |
| `clean` | remove `<TOP>`'s `.json` / `.pack.json` / `.fs` | no |
| `clean-all` | remove **everything** generated here -- all tops, all logs, formal work dirs, area baselines (tens of MB) | no |
| `clean-mem` | remove the generated memory images | no |

### Variables

| variable | default | meaning |
|---|---|---|
| `TOP` | `blink` | top-level module name |
| `FILELIST` | `blink.f` | `.f` list of sources, **order matters** |
| `CST` | `tangnano20k.cst` | pin constraints |
| `TEST` | `add` | which `tests/build/<name>/` to turn into memory images |
| `SYNTH_OPTS` | `-nowidelut` | extra `synth_gowin` flags |
| `FREQ_MHZ` | `27` | nextpnr timing target |
| `AREA_FILELIST` | `cpu_top_filelist.f` | filelist for `make area` only |

A `.f` file lists one source per line, `#` for **whole-line** comments only --
the Makefile strips `^\s*#` lines but not trailing comments, so a comment after
a filename would be passed to slang as a filename. **Order matters**: packages
and interfaces must precede anything that imports or instantiates them, and the
list must track additions to `rtl/pipeline/` or elaboration fails on an
unresolved instance.

## Commonly used commands

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

# Make it survive a power cycle
make flash-nv TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst

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

## Reading the board

Six LEDs, active-low, allocated 1+1+2+2 so they answer four different questions:

| LED | meaning |
|---|---|
| `[0]` | **heartbeat** -- free-running counter off the raw clock, independent of the core. Distinguishes "bad bitstream" from "stuck core". |
| `[1]` | **fetch activity** -- advances on every completed fetch. Blinks while running, **freezes on a hang**. No sticky flag can show this. |
| `[2]` | `tohost` written (program finished) |
| `[3]` | `tohost == 1` (program passed) |
| `[5:4]` | **driven by software** -- a store to `LED_ADDR` (`0x8000_1FFC`) latches its low 2 bits |

The software LEDs are a **snoop on the dmem write bus**, not a peripheral -- no
address decoder, no second bus slave. The store also lands in RAM, harmlessly.
Real MMIO belongs with the UART work ([UART_PLAN.md](UART_PLAN.md)).

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
| `rtl/cpu_top.sv` | synthesis top: wrapper, reset sync, LED panel |
| `rtl/bram_slave.sv` | `mem_if` slave backed by BSRAM |
| `cpu_top_filelist.f` | sources for the full CPU build |
| `cpu_filelist.f` | CPU sources without the FPGA wrapper (not a synthesis target -- see above) |
| `cpu_top.cst` | pin constraints for `cpu_top` |
| `tangnano20k.cst` | pin constraints for the `blink` smoke test |
| `blink.f` / `blink.v` | CPU-less LED blinker, for proving the board and flow |
| `mkmem.py` | program image generator |
| `area_report.py` | per-module area report (`make area`) |
| `formal/` | SymbiYosys equivalence proofs for the ALU and LSU rewrites |
| `AREA_OPTIMIZATION.md` | how the design was made to fit, including what failed |
| `UART_PLAN.md` | deferred UART + serial loader design |

## Known rough edges

- **The pin numbers in `cpu_top.cst` are unverified.** `led[1..5]` and
  `rst_n_btn` were extrapolated from a known-good `led0 = 15`. Wrong pins show
  up as dark LEDs, not as any kind of build error. Check them against the board
  documentation before trusting a dark board.
- **Timing margin is thinner than area margin.** 74% LUT4 and 22% FF, but Fmax
  is 33 MHz against a 27 MHz requirement. A change that lengthens a
  combinational path costs margin that is scarcer than the LUTs.
- **Changing the program requires a full re-synthesis** (~3 minutes plus PnR),
  because `$readmemh` runs at synthesis time. This is exactly what the serial
  loader in `UART_PLAN.md` is meant to fix.
