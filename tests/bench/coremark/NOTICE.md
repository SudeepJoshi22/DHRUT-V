The six protected benchmark files (`core_main.c`, `coremark.h`,
`core_list_join.c`, `core_matrix.c`, `core_state.c`, `core_util.c`) are
byte-identical to [EEMBC CoreMark revision
1f483d5b8316753a742cbf5590caf5bd0a4e4777](https://github.com/eembc/coremark/tree/1f483d5b8316753a742cbf5590caf5bd0a4e4777).
They retain their Apache-2.0 license headers. `UPSTREAM.sha256` records their
hashes; `python3 tools/check_coremark.py` checks them before testing the port.

The original DHRUT-V import came through `iammituraj/pequeno_riscv`.
Its changes to the protected files have now been removed. Platform changes
live in `core_portme.c` and `core_portme.h`:

- Timing uses the low 32 bits of `mcycle`, with unsigned subtraction.
- The single-context port requires an explicit positive `ITERATIONS`.
- With no UART, `ee_printf` observes upstream validation messages. A pass
  requires the explicit success message and no error; unknown seeds fail.
- `portable_fini` stores cycles, iterations and error status before signaling
  `tohost`. A compiler memory barrier preserves this ordering. It then halts,
  preventing `crt0` from overwriting a failure with main's zero return value.
- `CLOCKS_PER_SEC=1` is a simulation-only duration-check bypass supplied by
  `tools/simulate_c.sh`. It permits short correctness runs; it does **not**
  satisfy the ten-second run rule. Hardware builds must use the actual clock
  frequency and run for at least ten measured seconds.

See [BENCHMARKING.md](../BENCHMARKING.md) for conditions, results and limits.
