#!/usr/bin/env python3
"""Standalone UART loopback, FIFO and loader-channel checks; no board needed."""
from pathlib import Path
import sys
from cocotb_tools.runner import get_runner, get_results

ROOT = Path(__file__).resolve().parent.parent


def main():
    sys.path.insert(0, str(ROOT / "fpga/tests"))
    build = ROOT / "tests/build/uart"
    runner = get_runner("verilator")
    runner.build(sources=[ROOT / "rtl/interfaces/mem_if.sv", ROOT / "fpga/rtl/uart.sv",
                          ROOT / "fpga/tests/uart_tb.sv"],
                 hdl_toplevel="uart_tb", build_dir=build / "obj")
    results = runner.test(hdl_toplevel="uart_tb", test_module="test_uart", test_dir=build)
    tests, failures = get_results(results)
    assert tests == 1 and failures == 0, (tests, failures)


if __name__ == "__main__":
    main()
