# Benchmarking DHRUT-V

## Status and measurement boundary

Stage 1 validates the benchmark flow at **one iteration**. These measurements
are sensitive to startup state and are **not steady-state headline scores** or
comparisons with other processors. No hardware measurement or EEMBC
certification is claimed.

Dhrystone is the existing pqr5-derived **2.2** port with result self-checks.
CoreMark uses the pinned EEMBC sources listed in its [NOTICE](coremark/NOTICE.md).
Only its platform files differ from that upstream revision.

## Reproduce the runs

On this machine, the FPGA clone shares the stable clone's installed tools:

```bash
cd /home/sudeep/github/DHRUT-V-FPGA
source /home/sudeep/github/DHRUT-V/venv/bin/activate
```

That environment also adds GCC, Spike and Verilator to PATH. On another
machine, install those tools and cocotb/pyuvm first. Run simulations serially:
`tools/pyUVM` is a shared build directory. The memory contract check below uses
its own isolated build directory.

```bash
MEM_STALL_MODE=fixed CPU_TRACE=0 WAVES=0 \
  ./tools/simulate_c.sh dhrystone_fixed tests/bench/dhrystone/*.c -- \
  -DITERATIONS=1 -DDHRUTV_RTLSIM=1
./tools/bench_report.py dhrystone_fixed --kind dhrystone

MEM_STALL_MODE=fixed CPU_TRACE=0 WAVES=0 CYCLE_TIMEOUT=1000000 \
  ./tools/simulate_c.sh coremark_fixed tests/bench/coremark/*.c -- \
  -DITERATIONS=1 -DPERFORMANCE_RUN=1
./tools/bench_report.py coremark_fixed --kind coremark
```

`CPU_TRACE=0` skips the passive pipeline monitor and instruction tracer. The
DMEM monitor, result writes, tohost scoreboard, watchdog and RTL assertions
remain enabled. `WAVES=0` disables waveform generation. Neither changes the
benchmark's simulated clock. Trace generation stays on by default.

For benchmark sources, the C runner defaults to `fixed`; other C tests still
default to `random`. Explicit `MEM_STALL_MODE` overrides either default.
Each new build saves `build.json` with compiler version, complete command,
revision/dirty status, ELF/source hashes and trace/memory settings. The reporter
accepts `--json` to include those conditions. It refuses failed, unfinished,
zero-measurement or mismatched-ELF results.

### Compiler and flags

Measured with `riscv-none-elf-gcc (xPack GNU RISC-V Embedded GCC x86_64) 15.2.0`.
The C runner applies the same flags to every translation unit:

```text
-march=rv32im_zicsr -mabi=ilp32
-O2 -ffreestanding -fno-stack-protector -fno-builtin
-DCLOCKS_PER_SEC=1
-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles
<per-benchmark defines shown above>
-T tests/linker_c.ld tests/crt0.S <benchmark sources> -lgcc
```

No LTO or additional benchmark-specific optimizer flags are used. This is a
fully disclosed build configuration, not a claim of independently audited
Dhrystone run-rule compliance. The reference is Spike with
`--isa=rv32im_zicsr -m0x80000000:0x10000`; the DUT uses Verilator/cocotb/pyuvm.

### Memory modes

| Mode | Behavior | Purpose |
|---|---|---|
| `fixed` | Capture in IDLE, synchronous read, response in RESP, then IDLE | FPGA BRAM handshake model |
| `zero` | Legacy driver with no added stall loop | Controlled microarchitecture experiments |
| `random` | Legacy data stalls 1–5 cycles; fetch stalls 1–2 cycles on roughly 40% of requests | Timing variation for regressions |

“Fixed” describes the entire response protocol, not an extra Python
`await RisingEdge`. The latter added an extra cycle in Claude's unfinished
implementation. The revised driver is checked against the actual
`fpga/rtl/bram_slave.sv` for both clock phases, held/back-to-back requests,
redirects, flushes, resets, data and byte-write strobes. Clocked RTL masters
also check simulator scheduling: the Python driver samples the preceding
half-cycle so it cannot accept a newly launched CPU request one edge early:

```bash
python3 tools/check_memory_timing.py
```

This establishes the tested memory protocol. The Python memory remains a
sparse backing store; it does not enforce FPGA capacity or upper-address
aliasing. End-to-end cycle equality with the physical board remains a hardware
cross-check, not an inference from where a score sits between other scores.

## Results and derivation

Only cycles between the benchmark's own start/stop `mcycle` reads enter the
calculation. Total cocotb runtime also includes startup, BSS initialization and
reporting and must not replace that interval.

```text
Dhrystone cycles/run = (stop_mcycle - start_mcycle) / runs
DMIPS/MHz           = 1,000,000 / (1757 * cycles/run)
CoreMark/MHz        = iterations * 1,000,000 / timed_cycles
```

Clock frequency cancels in these per-MHz expressions. The timing port uses a
32-bit difference: the interval must be shorter than 2^32 cycles.

Measured on 2026-09-19 with `fixed`, `CPU_TRACE=0`, `WAVES=0`. Dhrystone was
re-run after the Stage 2 MDU ordering correction; CoreMark was cross-checked
in native `cpu_top` simulation and retained the same timed count:

| Benchmark | Iterations | Timed cycles | Derived value | DUT result |
|---|---:|---:|---:|---|
| Dhrystone | 1 | 759 | 0.750 DMIPS/MHz | PASS |
| CoreMark, performance seeds | 1 | 383,043 | 2.611 CoreMark/MHz | PASS |

These are **flow-validation figures only**. The report JSONs in
[`results/`](results/) retain ELF hashes, commands and available build metadata.
Both records include automatically captured build conditions. These replace
the earlier 724 / 355,050-cycle figures: clocked-master testing found that
Verilator delivered Python rising-edge callbacks after the CPU updated its
requests. Sampling those new requests made the model one edge too early.
The corrected figures agree exactly with native Verilator runs of `cpu_top`
and actual BRAM in the Stage 2 hardware branch (32 KB per memory). This is
still an RTL comparison, not a measurement of the physical board.
Both CoreMark seed configurations also passed Spike; the validation-seed
configuration has not been rerun on the DUT in this stage.

The memory contract check, protected-source hash checks, five Spike cases,
reporter rejection tests and deliberate DUT watchdog timeout check passed.
No full ASM/RISCOF regression was repeated. Structural Verilator lint passed
with nonfatal warnings; the repository's regular lint script still exits on
pre-existing mixed-timescale warnings in the unchanged RTL.

Claude's earlier Dhrystone values (557 zero, 812 old-fixed, 1,211 random)
are historical observations. In particular **812 does not describe the corrected
BRAM timing model**. Its original CoreMark run completed with `tohost=1`, but
GCC scheduled the result stores after that write, so the testbench stopped
before capturing them. It cannot supply a valid recorded score. Its error
checker also missed CRC diagnostics. The original artifacts remain under
`tests/build/coremark`; the original working diff/document were saved under
`tests/build/benchmark_handoff` (both ignored build artifacts).

## Validation and reporting limits

```bash
python3 tools/check_coremark.py
```

This checks all six protected source hashes and runs these fast Spike cases:
performance seeds, validation seeds, a corrupted expected CRC in an ELF copy,
unknown seeds, and a one-iteration run with the real 27 MHz time conversion.
The first two must pass; the last three must fail. It also verifies that result
stores precede `tohost` and that failure is never overwritten by a later pass.
The CRC injection changes only a generated ELF, never benchmark source.

`CLOCKS_PER_SEC=1` deliberately suppresses CoreMark's duration gate for short
simulation checks. These runs **do not satisfy CoreMark reporting rules**.
Simulating enough target cycles is possible but expensive; simulator wall time
is not the benchmark's target execution time. The source and seed requirements
are separate from the duration requirement. Self-measured results and laboratory
certification are also separate claims.

[EEMBC's run and reporting rules](https://github.com/eembc/coremark/blob/1f483d5b8316753a742cbf5590caf5bd0a4e4777/README.md#run-rules)
require at least ten measured seconds, both specified seed sets, a 2,000-byte
buffer, consistent flags and unmodified protected sources. Keep compiler,
flags, iterations, memory configuration, platform and validation status beside
any published figure.

## Deferred hardware work

1. Grow the FPGA's current 8 KB instruction/data memories to 32 KB each and
   check synthesis utilization and timing. Check the full linked image,
   data/BSS and reserved stack against the address map, not only `.text` size.
2. Implement [the UART and serial loader](../../fpga/UART_PLAN.md) to load
   programs and retrieve results without rebuilding the bitstream each time.
3. Sweep Dhrystone iterations on hardware (1, 100, 1,000, 10,000, 50,000) and
   examine convergence. Choose CoreMark iterations from measured duration so
   the final run lasts at least ten seconds; 400 is not inherently sufficient.
   At 27 MHz ten seconds corresponds to 270 million timed cycles. Use the
   actual clock frequency for `CLOCKS_PER_SEC`, not the simulation bypass.
4. Compare a low-iteration board run with this fixed-mode simulation before
   publishing any equivalence claim. Run and record both CoreMark seed sets.
