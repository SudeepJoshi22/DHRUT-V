# run_test.py

# At top of run_test.py
import logging

logger = logging.getLogger("my_cpu_tb")
logger.setLevel(logging.INFO)

# Console handler
console = logging.StreamHandler()
console.setLevel(logging.INFO)
console_formatter = logging.Formatter('%(asctime)s | %(levelname)-8s | %(name)s: %(message)s')
console.setFormatter(console_formatter)
logger.addHandler(console)

# File handler
file_handler = logging.FileHandler("simulation.log", mode='w')
file_handler.setLevel(logging.INFO)
file_handler.setFormatter(console_formatter)
logger.addHandler(file_handler)

# Use this logger everywhere instead of self.logger
# Example in monitor:
logger.info("Monitor started")

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer
from pyuvm import uvm_root
import tb_pyuvm.test_imem_bringup

# Optional: make it more verbose for debug
# logging.getLogger('pyuvm').setLevel(logging.DEBUG)
# logging.getLogger('cocotb').setLevel(logging.INFO)

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
