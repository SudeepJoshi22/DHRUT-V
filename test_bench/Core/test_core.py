import os
from pathlib import Path
import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.regression import TestFactory

# Constants
RESET_DURATION = 20  # Reset duration in ns

TEST_DURATION = 1000

@cocotb.test
async def test_core(dut):

    """Test the Apply Clock and reset to the top module"""

    # Generate a clock with a period of 10ns
    cocotb.fork(Clock(dut.clk, 10, units="ns").start())

    # Reset the DUT
    dut.rst_n.value = 0
    
    # Release reset after some time
    await Timer(RESET_DURATION, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk) 
    
    await Timer(TEST_DURATION, units="ns")

def run_tests():
    factory = TestFactor(test_core)
    factory.generate_tests()
 
if __name__ == "__main__":
    run_tests()
