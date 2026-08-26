# UART + serial program loader — deferred design

Status: **planned, not implemented.** Phase 1 (a program running on the board
with LEDs as the only indicator) is deliberately ahead of this. This document
records the design so it can be picked up without re-deriving it.

## Why this matters

Two problems that LEDs cannot solve:

1. **No output.** `ee_printf` / `uart_init` already exist as no-op stubs in
   `tests/bench/dhrystone/port.c` and `tests/bench/coremark/core_portme.c`,
   annotated *"no UART on this core (yet)"*. Filling them in is what makes
   Dhrystone and CoreMark print real numbers on hardware.
2. **Changing the program costs a full rebuild.** `$readmemh` is evaluated at
   *synthesis* time and BSRAM `INIT` is bitstream data, so the program is part
   of the bitstream. A one-instruction edit currently costs Yosys + nextpnr +
   `gowin_pack` + flash — minutes. A serial loader cuts that to seconds.

## Key finding: this must be a hardware loader, not a boot ROM

A conventional software bootloader — a boot ROM at the reset vector that
receives a program and writes it into RAM — **cannot be built here without a new
datapath.**

- `rtl/cpu_core.sv:98` wires `imem_if` only to `if_stage`.
- `rtl/pipeline/lsu.sv:11` gives the LSU only `dmem_if`.

**The CPU has no path to write instruction memory.** A boot ROM would require
building that bridge first, plus target firmware.

The alternative is a **loader FSM in the fabric** that owns the memory ports
while the core is held in reset, then releases it. Better here on three counts:

- No target firmware, no reset-vector change.
- **It works even if the core is broken** — decisive during bringup, since you
  can load and verify memory before trusting the pipeline.
- Instruction memory stays read-only from the CPU's side.

Because the core is in reset whenever the loader is active, the two never
contend, so they can share the memory's **single** port through an input mux —
preserving single-port BSRAM inference rather than forcing true dual-port.

## Architecture

```
cpu_top
├── CORE      cpu_core          core_rst_n = sys_rst_n && !loading
├── LOADER    prog_loader       owns memory + UART while loading
├── IMEM      bram_slave        4096 x 64-bit = 32 KB
├── DMEM      bram_slave        8192 x 32-bit = 32 KB
├── DBUS      dmem_splitter     decodes m_addr[31]
└── UART      uart              loader while loading, CPU after
```

## Address map

| Range | Target | Notes |
|---|---|---|
| `0x8000_0000` + | dmem BRAM | `m_addr[31] == 1` |
| `0x1000_0000` | UART TXDATA | W: `[7:0]` byte. R: `[31]` tx_busy |
| `0x1000_0004` | UART RXDATA | R: `[31]` rx_empty, `[7:0]` data; read pops |
| `0x1000_0008` | UART STATUS | R: `[0]` tx_busy, `[1]` rx_valid, `[2]` overrun |

`bram_slave` currently **aliases on purpose** — it ignores upper address bits so
`0x8000_0000` lands at index 0 with no decoder. That must stop for dmem once a
second slave exists. A one-bit decode on `m_addr[31]` suffices, since RAM is at
`0x8xxx_xxxx` and MMIO at `0x1xxx_xxxx`.

Note Phase 1's LED control is a **snoop**, not MMIO — `cpu_top` watches dmem
writes to `LED_ADDR` and the store also lands in RAM. When this decoder lands,
consider moving the LEDs to a real MMIO register and retiring the snoop.

## Wire protocol

Mirrors the existing memory model, in which `fpga/mkmem.py` writes both images
from one input and the two cocotb drivers each load `TEST_HEX` into their own
dict: the loader writes the **same byte stream into both imem and dmem** at the
same offset.

```
'D' 'H' 'R' 'V'      magic
len[31:0]            little-endian byte count
payload[len]         raw image bytes, from offset 0
sum[31:0]            32-bit sum of payload
```

Loader replies one byte on TX: `'K'` accepted, `'E'` checksum mismatch.

**Timeout fallback:** if no magic arrives within ~500 ms of reset, release the
core anyway and run whatever `$readmemh` baked into BRAM. This keeps
`make mem` + `make bitstream` working standalone, so a board with no host
attached still boots. Pressing reset re-enters the loader.

## Implementation notes

**New**
- `fpga/rtl/uart.sv` — 8N1 TX and RX, parameterised divisor. Small RX FIFO
  (depth 8) so a byte is not lost between polls. Must honour the same handshake
  as `bram_slave`: **`s_rdata` valid on the same cycle as `s_ready`**, required
  by `rtl/pipeline/lsu.sv:142-148`.
- `fpga/rtl/dmem_splitter.sv` — routes the CPU's `mem_if` to RAM or UART on
  `m_addr[31]`, muxing `s_ready`/`s_rdata` back. **Unmapped addresses must still
  answer**, or the LSU stalls forever (`internal_stall`, `lsu.sv:136`).
- `fpga/rtl/prog_loader.sv` — receive FSM, checksum, memory write port, core
  reset release, timeout counter.
- `fpga/loadprog.py` — host tool: frame an image, send it over `/dev/ttyUSB*`,
  wait for the ack. Host tooling alongside `mkmem.py`, not target firmware.

**Modified**
- `fpga/rtl/bram_slave.sv` — add a loader write port muxed into the *existing*
  single port:
  ```systemverilog
  wire p_en  = loading ? ld_en  : (state_q == S_IDLE && accept);
  wire p_idx = loading ? ld_idx : idx;
  wire p_we  = loading ? {BYTES{ld_we}} : (is_write ? bus.m_wstrb : '0);
  ```
  Keeping read and write in one `always_ff` with no array reset is what
  preserves BSRAM inference — see the comment block in that file.
- `fpga/rtl/cpu_top.sv` — split reset into `sys_rst_n` (POR + button, drives
  loader/UART) and `core_rst_n = sys_rst_n && !loading`. Bump depths.
- `fpga/cpu_top.cst` — add `uart_tx` / `uart_rx`. The onboard BL616 is a
  USB-serial bridge, so this enumerates as `/dev/ttyUSB*` with no extra wiring.
  **Pin numbers need confirming against the board docs.**

## Sizing

32 KB + 32 KB. 8 KB of dmem cannot hold `tests/linker_c.ld`'s 8 KB stack alone,
let alone `.data`/`.bss`, so the C benchmarks need the bump. That is roughly 70%
of the part's ~92 KB usable BSRAM; 16 + 16 is the fallback if PnR gets tight.

`LED_ADDR` in `cpu_top.sv` is currently the top word of the 8 KB dmem
(`0x8000_1FFC`) — **it must move when `DMEM_DEPTH` grows.**

## Baud

27 MHz / 115200 = 234.375. A divisor of 234 is −0.16% error, well inside 8N1
tolerance. No PLL needed.

## Verification

The loader and UART are testable in simulation and should be — a bad loader is
invisible on the board.

1. **UART loopback:** tie `uart_tx` to `uart_rx`, write bytes via the MMIO
   address, confirm they return through RXDATA.
2. **Loader:** drive a framed image into `uart_rx`, check imem/dmem contents and
   that `core_rst_n` releases. Include a bad-checksum case (expect `'E'`, core
   stays in reset) and the timeout path (no magic → core runs the baked image).
3. **Regression:** the dmem decoder sits in the CPU's load/store path, so re-run
   `lsu`, `lsu_forward`, `memtest` and diff retired traces against Spike per
   CLAUDE.md.

## Deferred within this

`ee_printf` stays a no-op until a follow-up pass; item 1 above tests the
peripheral instead.
