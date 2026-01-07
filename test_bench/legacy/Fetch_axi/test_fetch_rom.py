import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.regression import TestFactory

# Constants
RESET_DURATION = 20  # Reset duration in ns

@cocotb.test
async def test_fetch_rom(dut):

    """Test the Fetch-Rom interface with various inputs"""

    # Generate a clock with a period of 10ns
    cocotb.fork(Clock(dut.clk, 10, units="ns").start())

    # Reset the DUT
    dut.rst_n.value = 0
    dut.i_trap.value = 0
    dut.i_trap_pc.value = 0
    dut.i_boj.value = 0
    dut.i_boj_pc.value = 0
    dut.i_stall.value = 0
    dut.i_flush.value = 0

    # Release reset after some time
    await Timer(RESET_DURATION, units="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Test fetch operation
    await perform_fetch_test(dut)

    # Test trapping behavior
    await perform_trap_test(dut)

    # Test BOJ (Branch On Jump) behavior
    await perform_boj_test(dut)

    # Test stalling behavior
    await perform_stall_test(dut)

    # Test flush behavior
    await perform_flush_test(dut)

    # Test prediction output
    await perform_prediction_test(dut)

async def perform_fetch_test(dut):
    """Test the basic fetch operation"""
    await RisingEdge(dut.clk)
    dut.i_stall.value = 0
    dut.i_flush.value = 0

    # Allow fetch to operate normally
    for _ in range(10):
        await RisingEdge(dut.clk)
        assert dut.o_pc.value.is_resolvable, "PC output is not resolvable"
        assert dut.o_instr.value.is_resolvable, "Instruction output is not resolvable"
        assert dut.o_prediction.value.is_resolvable, "Prediction output is not resolvable"
        cocotb.log.info(f"PC: {dut.o_pc.value}, Instruction: {dut.o_instr.value}, Prediction: {dut.o_prediction.value}")

async def perform_trap_test(dut):
    """Test the trap functionality"""
    dut.i_trap.value = 1
    trap_pc = 0x12345678
    dut.i_trap_pc.value = trap_pc
    await RisingEdge(dut.clk)

    assert dut.o_pc == trap_pc, f"Expected trap PC {hex(trap_pc)}, but got {hex(dut.o_pc.value)}"
    dut.i_trap.value = 0  # Deactivate trap

async def perform_boj_test(dut):
    """Test the BOJ (Branch On Jump) functionality"""
    dut.i_boj.value = 1
    boj_pc = 0x87654321
    dut.i_boj_pc.value = boj_pc
    await RisingEdge(dut.clk)

    assert dut.o_pc == boj_pc, f"Expected BOJ PC {hex(boj_pc)}, but got {hex(dut.o_pc.value)}"
    dut.i_boj.value = 0  # Deactivate BOJ

async def perform_stall_test(dut):
    """Test the stall functionality"""
    dut.i_stall.value = 1
    prev_pc = dut.o_pc.value
    await RisingEdge(dut.clk)
    assert dut.o_pc == prev_pc, "PC changed during stall when it should remain constant"
    dut.i_stall.value = 0  # Release stall

async def perform_flush_test(dut):
    """Test the flush functionality"""
    dut.i_flush.value = 1
    await RisingEdge(dut.clk)
    dut.i_flush.value = 0  # Deactivate flush

    # Check that after a flush, fetch starts fetching instructions from a new PC (implementation dependent)
    new_pc = dut.o_pc.value
    assert new_pc != 0, "PC did not update after flush"  # This check assumes PC changes after flush

async def perform_prediction_test(dut):
    """Test the prediction output"""
    # Set up some simple conditions for prediction (may vary based on the actual implementation of Fetch)
    for _ in range(5):
        await RisingEdge(dut.clk)
        dut.i_stall.value = random.choice([0, 1])  # Randomly stall or unstuck
        dut.i_flush.value = random.choice([0, 1])  # Randomly flush
        cocotb.log.info(f"Prediction: {dut.o_prediction.value}")

def run_tests():
    factory = TestFactor(test_fetch_rom)
    factory.generate_tests()
 
if __name__ == "__main__":
    run_tests()
