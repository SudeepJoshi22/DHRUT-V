# run_test.py

# At top of run_test.py
import logging

logger = logging.getLogger("my_cpu_tb")
logger.setLevel(logging.INFO)

# File handler - ensure we start fresh and don't duplicate handlers
root_logger = logging.getLogger()
for h in root_logger.handlers[:]:
    if isinstance(h, logging.FileHandler):
        root_logger.removeHandler(h)

file_handler = logging.FileHandler("simulation.log", mode='w')
file_handler.setLevel(logging.DEBUG)
console_formatter = logging.Formatter(' %(levelname)-2s | %(name)s: %(message)s')
file_handler.setFormatter(console_formatter)

# Attach to root logger to capture everything in simulation.log
root_logger.setLevel(logging.DEBUG)
root_logger.addHandler(file_handler)

# For our specific monitor logger, just set its level; it will propagate to root
logger = logging.getLogger("my_cpu_tb")
logger.setLevel(logging.DEBUG)
# No manual console handler needed, cocotb handles console output

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer
from pyuvm import uvm_root

import tb_pyuvm.test_imem_bringup
import tb_pyuvm.test_dhrut_v

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

    # await uvm_root().run_test("IFBringUpTest")
    await uvm_root().run_test("DhrutVTest")
