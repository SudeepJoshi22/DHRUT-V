# rtl/csr — SystemRDL spec for the CSR register file

The CPU's CSR block is generated from `csr_regfile.rdl` via [PeakRDL](https://peakrdl.readthedocs.io). `rtl/pipeline/issue.sv` instantiates the generated `csr_regfile_gen` directly — this is the real CSR block, not a side artifact. Adding a CSR means editing the `.rdl` and regenerating, not hand-editing SystemVerilog.

## Files

- `csr_regfile.rdl` — the spec. Source of truth.
- `generate.sh` — regenerates `generated/` (and `html_ref/` with `docs`).
- `generated/` — tracked, reviewable in diffs.
- `html_ref/` — gitignored, local-only browsable reference (`./generate.sh docs`, open `html_ref/index.html`).

## Regenerating

```bash
./rtl/csr/generate.sh          # RTL only
./rtl/csr/generate.sh docs     # + local HTML reference
```

Installs `peakrdl`/`peakrdl-regblock` into `venv/` itself if missing.

## Adding a new CSR

1. Add a `reg <name>_reg { ... }` type to `csr_regfile.rdl` and instantiate it in the `addrmap` at the next free offset (offsets are sequential 4-byte slots, not real CSR numbers — see below).
2. Add the CSR# → offset mapping to the `unique case` in `issue.sv`'s `csr_rdl_addr`/`csr_rdata_now` blocks (mirrors the `.rdl`'s addrmap — keep both in sync).
3. If the field is hardware-writable (`hw=rw`), drive its `csr_hwif_in.<reg>.<field>.next`/`.we` in `issue.sv`'s hwif-drive block.
4. `./rtl/csr/generate.sh`, `./tools/lint.sh`, then a directed `tests/asm/*.S` test via `simulate.sh`.

## Two things worth knowing before touching this

- **Addressing isn't the real RISC-V CSR number.** Those aren't 4-byte-aligned (`systemrdl-compiler` rejects them directly), so the `.rdl` uses sequential offsets, and `issue.sv` translates the real CSR# to that offset by hand (`csr_rdl_addr` case statement).
- **`--cpuif passthrough`**, not a bus protocol — this block is a single point-to-point interface hand-integrated into `issue.sv` (one CSR op per cycle), plus separate hw-side ports (trap entry, mret) with no bus equivalent. Reads bypass the cpuif entirely and pull straight from `hwif_out` so read-modify-write still resolves in one cycle; only writes go through `s_cpuif_*`.
- **hw vs sw write priority**: PeakRDL's generated logic checks SW first, HW second on a same-cycle collision — opposite of trap-entry's old hand-written priority. Moot today (Issue resolves one instruction/cycle, so they can't collide except on the counters, where SW winning is desired), but revisit if superscalar issue ever lands.
