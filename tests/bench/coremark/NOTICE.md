`core_main.c`, `core_matrix.c`, `core_list_join.c`, `core_state.c`,
`core_util.c`, and `coremark.h` are vendored, near-verbatim, from
[iammituraj/pequeno_riscv](https://github.com/iammituraj/pequeno_riscv)
(`coremark/`), which in turn vendors the official EEMBC CoreMark 1.0
sources (Apache License 2.0; see the header of each file).

DHRUT-V-specific changes on top of the pqr5 port:
- `core_portme.h`/`core_portme.c` (rewritten for DHRUT-V, not carried
  over from pqr5): timing via the `mcycle` CSR instead of a
  memory-mapped counter, no UART/`ee_printf` output, final score
  exposed through `dhrutv_final_*` globals instead of printed text.
- `core_main.c`: at the very end of `main()`, stash the score into
  those globals and `return total_errors` instead of always returning
  0, so a nonzero exit code (visible via `tohost`) means a CRC/data
  check actually failed - search for `[DHRUT-V]`.
- Compiled with `-DCLOCKS_PER_SEC=1`: CoreMark's internal ">=10s
  measured run" sanity gate (`core_main.c`) is a real-time compliance
  rule that RTL simulation cannot satisfy; since `ee_printf` is a
  no-op here anyway, the human-readable "Iterations/Sec" text this
  feeds is unused - only the raw mcycle-based cycle/iteration counts
  captured externally matter for DHRUT-V's own DMIPS/CoreMark-per-MHz
  reporting (see `tools/bench_report.py`).
