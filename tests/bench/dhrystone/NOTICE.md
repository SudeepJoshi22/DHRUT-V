`dhrystone.c`, `dhrystone.h`, `dhrystone_main.c`, and `stats.h` are vendored,
near-verbatim, from [iammituraj/pequeno_riscv](https://github.com/iammituraj/pequeno_riscv)
(`dhrystone/`), itself a bare-metal RISC-V port of the classic Dhrystone 2.2
benchmark (Reinhold P. Weicker, 1988; C port by Rick Richardson / Steven
Pemberton). Dhrystone is public domain / freely redistributable.

DHRUT-V-specific changes on top of the pqr5 port:
- `dhrystone.h`: added a `DHRUTV_RTLSIM` timing branch (mcycle-CSR-based,
  RTL-sim-appropriate `Too_Small_Time`) alongside the existing branches -
  search for `[DHRUT-V]`.
- `dhrystone_main.c`: replaced the printed "should be" comparisons at the
  end of `main()` with an actual self-check that returns a nonzero,
  per-field failure bitmask instead of always returning 0 - search for
  `[DHRUT-V]`.
- `port.c` (new, DHRUT-V-only) replaces pqr5's `stats.c`/`ee_printf.c`:
  timing via the `mcycle` CSR instead of a memory-mapped counter, no-op
  UART/printf stubs (no UART on this core yet), and minimal
  `strcpy`/`strcmp` since the build is `-nostdlib`.
