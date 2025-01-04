import os
from pathlib import Path
import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.regression import TestFactory

# Constants
RESET_DURATION = random.randint(10,25)   # Reset duration in ns

@cocotb.test
async def test_fetch_imem_interface(dut):
    """Test the Fetch-Rom interface with various inputs"""

    # Generate a clock with a period of 10ns
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Reset the DUT
    dut.rst_n.value = 0
    dut.stall.value = 0

    cocotb.log.info("Reset all the values")
    
    # Release reset after some time
    await Timer(RESET_DURATION, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    #dut.rst_n.value = 0
    
    # Test fetch operation
    await perform_fetch_test(dut)

    # Test stalling behavior
    await perform_stall_test(dut)


    for _ in range(10):
        await RisingEdge(dut.clk)


async def perform_fetch_test(dut):
    """Test the basic fetch operation"""
    await RisingEdge(dut.clk)
    # Allow fetch to operate normally
    
    
    for _ in range(15):
        await RisingEdge(dut.clk)
   
    dut.rst_n.value = 0
    
    # Release reset after some time
    await Timer(RESET_DURATION, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
		
    for _ in range(15):
        await RisingEdge(dut.clk)

async def perform_stall_test(dut):
    """Test the stall functionality"""
    dut.stall.value = 1
    await RisingEdge(dut.clk)
    #assert dut.o_pc == prev_pc, "PC changed during stall when it should remain constant"
    dut.stall.value = 0  # Release stall

def run_tests():
    factory = TestFactor(test_fetch_imem_interface)
    factory.generate_tests()
 
if __name__ == "__main__":
    run_tests()
