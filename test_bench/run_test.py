# run_test.py

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer
from pyuvm import uvm_root, ConfigDB
import tb_pyuvm.test_imem_bringup

@cocotb.test()
async def run_test(dut):
    """
    cocotb entry point.
    """
    # Clock generation
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    # Reset
    dut.rst_n.value = 0
    await Timer(40, unit="ns")
    dut.rst_n.value = 1
    cocotb.log.info("Reset released")

    await uvm_root().run_test("IFBringUpTest")
