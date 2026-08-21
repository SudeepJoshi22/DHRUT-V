# rtl/csr — SystemRDL spec for the CSR register file

This directory is a **validation pass**, not the thing that builds the CPU.
The core still compiles entirely from the hand-written `rtl/pipeline/csr.sv`,
instantiated inside `rtl/pipeline/issue.sv`. Nothing here is referenced by
`tb_top.sv`, `tools/lint.sh`, or `tools/simulate.sh`. See the "CSR / Trap
Support" section of the top-level `README.md` for the user-facing summary;
this file is the "how do I touch this again in six months" reference.

## Why this exists

`rtl/pipeline/csr.sv` was reverse-engineered field-by-field into
[SystemRDL](https://www.accellera.org/downloads/standards/systemrdl)
(`csr_regfile.rdl`), then RTL and documentation were regenerated from that
spec via [PeakRDL](https://peakrdl.readthedocs.io), as a cross-check: if the
spec is right, the generated RTL and the hand-written RTL should agree on
every register's layout, reset value, and access behavior. Where they don't
(or where SystemRDL can't cleanly express what the hand-written RTL does),
that's flagged directly in `csr_regfile.rdl`'s comments rather than papered
over.

## Files

| Path | Tracked in git? | What it is |
|---|---|---|
| `csr_regfile.rdl` | Yes | The spec. Source of truth for everything else in this directory. |
| `generate.sh` | Yes | Regenerates `generated/` (and optionally `html_ref/`) from the `.rdl`. |
| `generated/` | Yes | `peakrdl regblock` output (SystemVerilog). Checked in so the diff is reviewable, same as any other generated-but-committed artifact in this repo. |
| `html_ref/` | **No** (gitignored) | `peakrdl html` output — a local, browsable register reference (`html_ref/index.html`). Regenerate on demand; not meant to be committed (it's ~8MB of vendored fonts/JS per generation). |

## Regenerating

```bash
# from the repo root, with venv/ set up (./tools/install.sh, or just
# `venv/bin/pip install peakrdl peakrdl-regblock` if you already have the
# rest of the toolchain)
./rtl/csr/generate.sh          # regenerates generated/ only
./rtl/csr/generate.sh docs     # also regenerates html_ref/ for local browsing
```

The script installs `peakrdl`/`peakrdl-regblock` into `venv/` itself if
they're missing, so a fresh clone + `./tools/install.sh` + this script is
enough — no separate toolchain to set up.

## Addressing: why the .rdl doesn't use real RISC-V CSR numbers

RISC-V CSR numbers (`mstatus`=0x300, `mepc`=0x341, ...) are a flat 12-bit
*index*, not a byte-addressed memory offset, and most of them aren't
4-byte-aligned. SystemRDL requires non-overlapping, naturally-sized register
footprints — using the raw CSR numbers as `.rdl` addresses was tried and
**hard-rejected** by `systemrdl-compiler` (every adjacent register overlaps).

So `csr_regfile.rdl` uses plain sequential 4-byte offsets instead. The real
mapping (documented in both the file header and just above the `addrmap`'s
instance list) is:

| RDL offset | RISC-V CSR # | Register |
|---|---|---|
| 0x00 | 0x300 | mstatus |
| 0x04 | 0x301 | misa |
| 0x08 | 0x304 | mie |
| 0x0C | 0x305 | mtvec |
| 0x10 | 0x340 | mscratch |
| 0x14 | 0x341 | mepc |
| 0x18 | 0x342 | mcause |
| 0x1C | 0x343 | mtval |
| 0x20 | 0x344 | mip |
| 0x24 | 0xB00 | mcycle |
| 0x28 | 0xB02 | minstret |
| 0x2C | 0xB80 | mcycleh |
| 0x30 | 0xB82 | minstreth |
| 0x34 | 0xF11 | mvendorid |
| 0x38 | 0xF12 | marchid |
| 0x3C | 0xF13 | mimpid |
| 0x40 | 0xF14 | mhartid |

If this ever replaces the hand-written module, `issue.sv`'s dispatch logic
(today: `i_csr_addr = buf_uop_q.imm[11:0]`, the raw CSR number, straight
through) needs an explicit CSR-number → RDL-offset translation table in
front of the generated block's `--cpuif passthrough` address input.

## `--cpuif passthrough`, and why not a bus protocol

`csr_regfile` isn't bus-attached. It's a single direct point-to-point
interface hand-integrated into `issue.sv`: one atomic RISC-V CSR instruction
resolved per cycle (address + write-data + write-enable in, old-value +
invalid-address out), plus two extra hardware-side write ports (trap entry,
mret) with no bus equivalent at all. None of PeakRDL's bus cpuifs
(APB/AXI-lite/AXI4/Avalon/Wishbone/OBI) apply, so this spec targets
`--cpuif passthrough` — PeakRDL's option for exactly this "wrap it in your
own access logic" case.

## Known open questions (read before promoting this beyond "validation pass")

Both are called out in `csr_regfile.rdl`'s comments too; repeated here since
they're the two things that would need resolving before the generated block
could realistically replace `rtl/pipeline/csr.sv`:

1. **CSR addressing** (see table above) — needs the translation layer
   described, not just a drop-in swap.
2. **hw vs sw write priority on `hw=rw` fields.** PeakRDL's default generated
   logic for a field with `hw=rw` + an explicit `we` checks **software
   first, hardware second** on a same-cycle collision. The hand-written RTL
   does the opposite: `if (trap) ... else if (mret) ... else if (sw_write)
   ...` — hardware (trap entry) always wins. Today this is unobservable:
   Issue resolves exactly one instruction per cycle, so a CSR-writing
   instruction and a trap can never coincide on the same cycle. It would
   become a real, silent divergence the moment superscalar issue exists
   (floated as a possible future milestone). Not fixed here — options are
   forcing hw-priority via an RDL `swwe` veto signal, or leaving it since
   it's currently moot. Whoever picks this back up should decide, not
   assume either way.

Other things flagged directly in `csr_regfile.rdl`'s header (mcycle/minstret
sw-write-vs-autoincrement bit-range races, the mepc bits[1:0] masking
asymmetry between sw and hw write paths, mip/MPP modeling choices) are
lower-stakes and can be read there when relevant.

## How to expand this (e.g. adding CSRs for a future extension)

1. Add a new `reg <name>_reg { ... }` type definition to `csr_regfile.rdl`
   (mirror the existing entries — pick `sw`/`hw` access per field based on
   what the *intended* hardware behavior is, not by copying the nearest
   existing field).
2. Instantiate it in the `addrmap` block at the next free sequential offset,
   and add a row to the mapping table (both here and in the `.rdl`'s own
   comment block) recording which real CSR number it corresponds to.
3. Run `./rtl/csr/generate.sh docs` and sanity-check the new register in
   `html_ref/index.html`.
4. If/when this directory starts actually generating the CPU's real CSR
   block (not just a comparison artifact), the corresponding hand-written
   RTL changes and the `issue.sv` CSR-address translation table need to move
   in lockstep — don't let the `.rdl` drift ahead of what's actually wired
   into the pipeline, or behind it either.
