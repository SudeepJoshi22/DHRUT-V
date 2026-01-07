# run_if_test.py
import sys
from pathlib import Path

import cocotb

from pyuvm import uvm_root

# Make test_bench visible
sys.path.append(str(Path(__file__).parent.resolve()))

import tb_pyuvm.test_imem_bringup  # noqa: F401

@cocotb.test()
async def run_if_test(dut):
    """
    Dummy cocotb entry point.
    pyUVM takes over from here.
    """
    await uvm_root().run_test("IfSmokeTest")
