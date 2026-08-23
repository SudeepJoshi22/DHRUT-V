#!/usr/bin/env python3
"""Compute CPI/IPC (and, for known benchmarks, a score) from the mcycle/
minstret CSR values a benchmark run left behind.

DHRUT-V has no UART, so benchmarks (tests/bench/dhrystone,
tests/bench/coremark) can't print their own report - they stash results
in a handful of global variables instead (dhrutv_final_* - see each
benchmark's port.c/core_portme.c) and exit through the usual `tohost`
pass/fail convention. This script reads those values back out of the
ELF's final memory image via the cocotb-produced VCD, so a human/CI can
still get a normal-looking report after an RTL run.

Usage:
    tools/bench_report.py <test_name> [--kind dhrystone|coremark|generic]

Reads tests/build/<test_name>/dump.vcd for the final value of the named
global(s), matched against tests/build/<test_name>/<test_name>.elf's
symbol table so it doesn't need to know their addresses ahead of time.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def elf_symbol_addr(elf_path, name):
    out = subprocess.run(
        ["riscv-none-elf-nm", str(elf_path)], capture_output=True, text=True, check=True
    ).stdout
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == name:
            return int(parts[0], 16)
    return None


def read_final_globals_from_trace(sim_log_path, elf_path, names):
    """
    DHRUT-V's dmem is modeled as a Python dict inside the cocotb
    testbench (not real RTL memory), so it never appears in the VCD.
    Instead, replay the 'DMEM WRITE addr=0x... wdata=0x... wstrb=0x...'
    lines dmem_monitor.py already logs to simulation.log, in order, to
    reconstruct the final value at each requested global's address.
    """
    addrs = {name: elf_symbol_addr(elf_path, name) for name in names}
    missing = [n for n, a in addrs.items() if a is None]
    if missing:
        print(f"warning: symbol(s) not found in {elf_path}: {missing}", file=sys.stderr)

    mem = {}
    pat = re.compile(r"DMEM WRITE addr=0x([0-9a-fA-F]+) wdata=0x([0-9a-fA-F]+) wstrb=0x([0-9a-fA-F]+)")
    with open(sim_log_path) as f:
        for line in f:
            m = pat.search(line)
            if not m:
                continue
            addr = int(m.group(1), 16) & ~3
            wdata = int(m.group(2), 16)
            wstrb = int(m.group(3), 16)
            old = mem.get(addr, 0)
            new = old
            for i in range(4):
                if (wstrb >> i) & 1:
                    byte = (wdata >> (8 * i)) & 0xFF
                    new &= ~(0xFF << (8 * i))
                    new |= byte << (8 * i)
            mem[addr] = new

    results = {}
    for name, addr in addrs.items():
        if addr is None:
            results[name] = None
            continue
        aligned = addr & ~3
        results[name] = mem.get(aligned)
    return results


def to_signed32(v):
    if v is None:
        return None
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("test_name")
    ap.add_argument("--kind", choices=["dhrystone", "coremark", "generic"], default="generic")
    args = ap.parse_args()

    build_dir = ROOT / "tests" / "build" / args.test_name
    elf = build_dir / f"{args.test_name}.elf"
    sim_log = build_dir / "simulation.log"

    if not elf.exists() or not sim_log.exists():
        print(f"error: expected {elf} and {sim_log} - run tools/simulate_c.sh first", file=sys.stderr)
        sys.exit(1)

    if args.kind == "dhrystone":
        names = [
            "dhrutv_final_dmips",
            "dhrutv_final_mhz",
            "dhrutv_final_cycles",
            "dhrutv_final_runs",
        ]
    elif args.kind == "coremark":
        names = ["dhrutv_final_iterations", "dhrutv_final_total_cycles", "dhrutv_final_mhz"]
    else:
        names = ["dhrutv_final_cycles" if args.kind != "coremark" else "dhrutv_final_total_cycles"]

    vals = read_final_globals_from_trace(sim_log, elf, names)
    vals = {k: to_signed32(v) for k, v in vals.items()}

    print(f"# Benchmark report: {args.test_name} ({args.kind})")
    print()

    if args.kind == "dhrystone":
        cycles = vals.get("dhrutv_final_cycles")
        runs = vals.get("dhrutv_final_runs")

        print("## 1. Raw data captured from the mcycle CSR")
        print(f"    cycles elapsed (Start_Timer -> Stop_Timer) = {cycles}")
        print(f"    Number_Of_Runs                             = {runs}")

        if cycles and runs:
            cycles_per_run = cycles / runs
            print()
            print("## 2. Derived: cycles per Dhrystone run")
            print(f"    cycles_per_run = cycles / runs = {cycles} / {runs} = {cycles_per_run:.1f}")

            print()
            print("## 3. Derived: DMIPS/MHz")
            print("    DMIPS/MHz = 1,000,000 / (1757 x cycles_per_run)")
            print("    (the 1757 is fixed: a VAX-11/780 does 1757 Dhrystones/sec = 1 MIPS,")
            print("     by definition. Any assumed clock frequency cancels out of this")
            print("     formula algebraically - see NOTICE.md - so none is needed here.)")
            dmips_per_mhz = 1_000_000 / (1757 * cycles_per_run)
            print(f"    = 1,000,000 / (1757 x {cycles_per_run:.1f}) = {dmips_per_mhz:.3f}")

        if cycles and runs:
            assumed_mhz = vals.get("dhrutv_final_mhz") or 0
            print()
            print("## 4. On-target cross-check (computed inside dhrystone_main.c itself,")
            print("     using an assumed 100MHz clock that cancels out the same way)")
            print(f"    dhrutv_final_dmips = {vals.get('dhrutv_final_dmips')}"
                  f"  (== DMIPS/MHz x assumed_mhz = {dmips_per_mhz:.3f} x {assumed_mhz}"
                  f" -> rounds to {round(dmips_per_mhz * assumed_mhz)})")

    elif args.kind == "coremark":
        cycles = vals.get("dhrutv_final_total_cycles")
        iters = vals.get("dhrutv_final_iterations")

        print("## 1. Raw data captured from the mcycle CSR")
        print(f"    total cycles elapsed (start_time -> stop_time) = {cycles}")
        print(f"    Iterations completed                           = {iters}")

        if cycles and iters:
            cycles_per_iter = cycles / iters
            print()
            print("## 2. Derived: cycles per CoreMark iteration")
            print(f"    cycles_per_iter = cycles / iterations = {cycles} / {iters} = {cycles_per_iter:.1f}")

            print()
            print("## 3. Derived: CoreMark/MHz")
            print("    CoreMark/MHz = iterations x 1,000,000 / cycles")
            print("    (equivalently 1,000,000 / cycles_per_iter - any assumed clock")
            print("     frequency cancels out of this formula the same way DMIPS/MHz's does)")
            coremark_per_mhz = iters * 1_000_000 / cycles
            print(f"    = {iters} x 1,000,000 / {cycles} = {coremark_per_mhz:.3f}")

    else:
        for k, v in vals.items():
            print(f"{k:28s} = {v}")


if __name__ == "__main__":
    main()
