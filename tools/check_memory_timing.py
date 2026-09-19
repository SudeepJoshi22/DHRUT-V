#!/usr/bin/env python3
"""Run the fixed-memory contract check in an isolated, small Verilator build."""
import os
import sys
from pathlib import Path
from cocotb_tools.runner import get_runner, get_results

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "tests/build/memory_timing"
TESTS = ROOT / "test_bench/memory_timing"


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "imem.hex").write_text("".join(
        f"{i + 2:08x}{i + 1:08x}\n" for i in range(0, 32, 2)))
    for lane in range(4):
        (BUILD / f"dmem_b{lane}.hex").write_text("".join(
            f"{((i + 1) >> (lane * 8)) & 255:02x}\n" for i in range(32)))
    sys.path[:0] = [str(ROOT / "test_bench"), str(TESTS)]
    os.environ["MEM_STALL_MODE"] = "fixed"
    runner = get_runner("verilator")
    runner.build(sources=[ROOT / "rtl/interfaces/mem_if.sv",
                          ROOT / "fpga/rtl/bram_slave.sv",
                          TESTS / "memory_timing.sv"],
                 hdl_toplevel="memory_timing", build_dir=BUILD / "build")
    results = runner.test(hdl_toplevel="memory_timing", test_module="test_memory_timing",
                          test_dir=BUILD)
    tests, failures = get_results(results)
    assert tests == 1 and failures == 0, (tests, failures)


if __name__ == "__main__":
    main()
