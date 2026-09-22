# Fitting DHRUT-V onto the Tang Nano 20K

How the original 8 KB `cpu_top` build went from 3.4x over the GW2AR-18 to
placing with room to spare, what each change was actually worth, which ideas
backfired, and where its remaining headroom was. This is a historical record of
the 2026-09-14 pre-RV32M, pre-UART configuration. The current 32 KB/UART build
uses 17,054 LUT4 and reaches 28.33 MHz routed Fmax; see [README.md](README.md).

## Result

| resource | first synthesis | optimized 8 KB build | budget | |
|---|---:|---:|---:|---|
| **LUT4** (nextpnr) | — | **15,385** | 20,736 | **74%** |
| LUT4 (yosys stat) | 70,507 | 14,257 | 20,736 | 69% |
| FF | 19,845 | 3,440 | 15,552 | 22% |
| BSRAM | 4 | 8 | 46 | 17% |
| LUT-RAM (RAM16SDP4) | 0 | 15 | 648 | 2% |
| MUX2_LUT5..8 | 23,854 | 0 | — | — |

That build placed, routed and **met timing at 27 MHz** (Fmax 33.06 MHz, about
22% margin).

**LUT4 down ~76%, flip-flops down ~83%.** No ISA behaviour changed: every step
was gated on the retired-instruction trace against Spike, and the two rewrites
that altered logic carry machine-checked equivalence proofs.

nextpnr is the authority, not `yosys stat` -- it runs roughly 1,100-1,250 LUT4
above the yosys estimate because of packing. The 101% run failed outright
(*"Unable to find legal placement for all cells"*). The 87% run **placed but
would not route**. Only the 74% run completes.

## Two things this exercise taught, the hard way

**1. Pre-techmap cell counts do not predict post-ABC9 LUTs.**
Shrinking the fetch queue from depth 8 to 4 removed 2,771 cells in the
pre-techmap stat and then *added 2,750 LUT4* after ABC9. It passed every test
and was still the wrong change. Only a full `synth_gowin` run counts, and the
final word belongs to nextpnr.

**2. Fitting is not the same as routing.**
The design once reached 87% LUT4 -- comfortably "under budget" -- and the
router still failed, thrashing for 65 minutes with overused wires climbing
18 -> 426 over 136,000 iterations. Utilisation is necessary, not sufficient;
the nets have to route too, and wide-LUT clusters make that much harder.

**3. Moving an array into RAM is not automatically a win.**
It is a win when the array lands on a bank boundary and a loss when it does
not, because the bank decode and output mux can cost more than the storage
they replace. Both of this project's failed changes were this mistake.

`fpga/area_report.py` (`make area`) exists because of lesson 1: it always runs
synthesis to completion and `--compare` shows the delta *per module*, so a
change that helps one block while hurting another cannot hide in the total.

## What worked

### 1. BPU table: 256 -> 32 entries, then into distributed RAM, then 16 entries

The branch predictor was the whole problem, not the superscalar core and not
the memories. `bpu.sv` stored a 66-bit entry (full 32-bit PC tag + 32-bit
target + 2-bit counter) in a **packed** array of 256 with an **async reset over
every entry**. That is 16,896 flip-flops -- 85% of the design's registers --
plus two 256:1 x 66-bit read mux trees and a 256-way write decoder.

Three separate properties each independently blocked RAM inference:

- **packed** -- one wide vector; synthesis can only build that from
  flip-flops and mux trees
- **async reset over every entry** -- forces flip-flops outright
- **two write ports** -- rules out every RAM primitive on this part

Fixed in stages:

| step | LUT4 | note |
|---|---:|---|
| start | 70,507 | |
| depth 256 -> 32 | 28,192 | |
| tag 32 -> 10 bits | 23,777 | 22 of 66 bits per entry were tag |
| unpacked + `initial` + one write port | 19,724 | lands in RAM16SDP4 |
| depth 32 -> **16** | **17,015** | one bank exactly; bank select disappears |

That last step is the interesting one: at depth 32 the table needed *two*
RAM16SDP4 banks plus decode and an output mux, and that selection logic cost
2,709 LUT4 -- more than the storage it was selecting. RAM16SDP4 is 16 deep
(`abits 4` in `gowin/lutrams.txt`), so depth 16 is exactly one bank.

**Serialising the write ports is the one real behaviour change.** A resolved
update and a new allocation could previously both commit in a cycle if they hit
different indices; the update now always wins and the allocation is dropped
whenever they coincide. That is prediction quality only -- an allocation is a
guess about an instruction that has not executed, so dropping one means the next
fetch of that branch misses and allocates then. A resolved update is fact and is
never lost. Issue re-resolves every branch and redirects on a mismatch, so no
BPU decision reaches architectural state.

`assert_single_writer` became structurally impossible and was replaced by
`assert_update_never_lost` and `assert_write_lands`, which check what the
serialisation could actually break.

**Measured IPC cost: none on the available tests.** A sweep of
256/128/64/32/16 at `MEM_STALL_MODE=zero` gives `bpu_loop` IPC 1.3502 and
`bpu_pattern` 1.1257 at *every* depth, cycle for cycle, because these tests'
branch sites fit inside one aliasing window. Denser code (Dhrystone, CoreMark)
would pay something; no test here can show it.

### 2. A dead data memory (a correctness bug, found while chasing area)

Nothing drove `dmem_if.m_flush`. `ifetch.sv` drives the imem side; the data
side was left dangling. Undriven, synthesis treats it as don't-care and folds
it, which made `bram_slave`'s `accept = m_valid && !m_flush` constant-false --
and `opt` then deleted the **entire 2048x32 data memory as dead code**. Loads
would have returned a constant on hardware.

Nothing in the test suite could have caught it: the cocotb dmem driver never
reads `m_flush`, and `bram_slave` is not instantiated in the sim testbench at
all. Memories surviving `opt` went 3 -> 7.

### 3. Byte-lane split for the writable BRAM

With the data memory alive again it had to actually *infer*. Yosys' Gowin rules
have no mapping for a read combined with a byte-masked **partial** write, so it
would have landed in fabric. Splitting into byte-wide arrays, each written whole
under its own strobe, maps all four lanes via `$__GOWIN_SP_` (BSRAM 4 -> 8).
The ROM path keeps the original shape -- `WRITABLE=0` folds the write branch
away, which is why imem always inferred and dmem never did.

Splitting a word-wide `$readmemh` inside an `initial` does not elaborate under
slang, so `mkmem.py` emits `dmem_init_b0..b3.hex`.

### 4. Datapath sharing in ALU and LSU (no area win, kept anyway)

Both had one operator per `case` arm, so each arm built its own hardware:
`alu.sv` inferred three 32-bit shifters and three subtractors; `lsu.sv` built a
shifter per access size and a case arm per (size, offset) pair. Both now share
one adder / one shifter.

**Measured effect: ~neutral** (23,777 -> 23,803). Yosys' `opt_share` was already
merging most of it. Kept because they are proven-equivalent and clearer, but no
win is claimed.

Both carry SymbiYosys/Z3 proofs in `fpga/formal/` -- combinational, so BMC depth
1 is a complete proof rather than a bounded one. `alu_equiv` covers every
`(op1, op2, alu_op)`; `lsu_equiv` covers every
`(data, offset, size, sign_extend, is_store)`.

### 5. `synth_gowin -nowidelut` -- the change that actually closed it

Worth its own entry because it is a *synthesis flag*, not RTL, and because the
result is counter-intuitive:

| | default | `-nowidelut` |
|---|---:|---:|
| LUT4 (yosys) | 17,015 | **14,257** |
| MUX2_LUT5..8 | 5,706 | **0** |
| LUT4 (nextpnr) | 18,143 (87%) | **15,385 (74%)** |
| router | diverged | **converged** |

Mapping to plain LUT4s instead of the MUX2_LUT5..8 wide-LUT tree is *smaller*,
not larger. And it helps twice over: wide LUTs tie groups of LUT4s into
clusters that must be placed adjacently, so removing them frees the placer as
well as shrinking the design. This is what turned a design that would not route
into one that does.

`-noabc9` made no difference at all (17,015 either way). The design needs
27 MHz and ABC9 optimises for delay, so an area-oriented ABC script may still
be worth trying, but the wide-LUT flag was the lever that mattered.

Both the Makefile and `area_report.py` read `SYNTH_OPTS`, so the report always
measures what `make bitstream` builds.

### 6. A missing clock constraint

nextpnr had no target frequency and was defaulting to 12 MHz, reporting
"PASS at 12.00 MHz". The Fmax it printed was an informational by-product, not a
met constraint -- timing was never actually checked against the board's 27 MHz
oscillator. `--freq 27` (Makefile `FREQ_MHZ`) fixes that; the design now
reports "PASS at 27.00 MHz" with Fmax 33.06 MHz.

### 7. Two SystemVerilog portability fixes

Found by `yosys -m slang`, hidden by Verilator: `lsu.sv` used `uop_t` with no
file-scope import (Verilator shares one `$unit`; slang follows the LRM), and six
`always_ff` blocks folded a synchronous `i_flush` into an asynchronous reset
condition.

## What failed

Recorded so nobody retries them blind.

| change | looked like | actually | why |
|---|---|---|---|
| `FQ_DEPTH` 8 -> 4 | -2,771 cells pre-map | **+2,750 LUT4** | depth 4 pushed the queue out of a shift-register-friendly shape |
| `ras.sv` stack into RAM | FF -256, LUT-RAM 30 -> 38 | **+2,252 LUT4** | 8 entries x 32 bits does not fill a bank; decode + read mux cost more than the FFs saved |

Both passed their tests. Both were wrong. This is the entire argument for
measuring each change in isolation against a real synthesis.

## Where the remaining headroom is

~2,600 LUT4 of margin at 87%. If more is needed:

**`ARF.sv` -- the largest remaining block (~28% of LUTs).**
A 32x32 register file with 4 read ports and 2 write ports, asynchronous read.
It cannot use Gowin LUT-RAM directly: `lutrams.txt` gives `abits 4` (16 deep,
needs 32) and a single write port. The known technique is a *live value table* --
two banks, one per write port, plus a per-register bit recording which bank
holds the current value, with reads muxing between them. Each bank is then
single-write and could be replicated per read port. Real work, and the read mux
does not disappear, so measure before committing.

**`issue.sv` operand selection.** Mux-dominated (2-wide issue means four operand
paths). Sharing selection logic between lanes is possible but touches the
hazard/bypass interaction, which is the riskiest area in the core.

**`fetch_queue.sv` entry width, NOT depth.** The entry is 97 bits
(`pc`, `instr`, `pred_taken`, `pred_target`). `pc` is sequential except after a
redirect and could be a base plus per-entry offset; `pred_target` only matters
for entries predicted taken. Depth is proven counterproductive -- do not touch
it.

**CSR trimming.** `csr_regfile_gen` + `csr_unit` is a few thousand LUT4 for 17
CSRs including 64-bit `mcycle`/`minstret` pairs. Narrowing the counters is
visible to software and would need a decision, not a silent change.

**`scoreboard.sv`.** It was inert in this pre-RV32M build because bypass always
covered the fixed-latency producers. It is live in the current core: the
non-blocking MDU has no bypass path, so consumers of its destination must wait.

**Further synthesis flow tuning.** `-nowidelut` is already in use and was the
single largest win of the whole exercise; `-noabc9` changed nothing. An
area-oriented ABC script remains a low-RTL-risk experiment, but must be judged
against the current 28.33 MHz routed result rather than the historical 33 MHz.

**Timing margin is the thing to watch, not area.** The current 32 KB/UART build
has less headroom than this historical 74%-LUT result: routed Fmax is 28.33 MHz
against a 27 MHz requirement. Any future change that lengthens a combinational
path costs margin that is scarcer than LUTs.

## Measuring

```bash
cd fpga
make area                              # rank modules, print the budget verdict
make area ARGS="--save base.json"      # record a baseline
make area ARGS="--compare base.json"   # per-module delta after a change
make bitstream TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst
```

The per-module table sums to more than the flat total on purpose: it is built
with hierarchy preserved, which disables cross-module optimisation. Rank with
the table, judge fit with the verdict, and confirm with nextpnr.

Counting note: `ALU` cells have their **own** 15,552-cell budget and do not
compete for LUT4 (nextpnr reports them separately, ~6% used). `MUX2_LUT5..8`
use dedicated slice mux hardware, and the LUT4s they combine are already
counted, so they are excluded too.
