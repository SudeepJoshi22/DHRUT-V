import os
from pathlib import Path
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
from cocotb.regression import TestFactory

@cocotb.test
async def test_fetch_rom(dut):

      
    # Set initial input value to prevent it from floating
   
    clock = Clock(dut.clk, 20, units="ns") 
    cocotb.start_soon(clock.start(start_high=False))

    await RisingEdge(dut.clk)
    # detected_val = 0  
    dut.rst.value = 1  
    await RisingEdge(dut.clk)  
    dut.rst.value = 0  
    await RisingEdge(dut.clk)  

    input_sequence = [0, 1, 0, 1, 0, 1, 1] 
    expected_outputs = [0, 0, 0, 1, 0, 1, 0]  

    for i in range(len(input_sequence)):
        dut.d.value = input_sequence[i]  
        await RisingEdge(dut.clk) 
        
        detected = dut.detected.value
        print(f"input: {input_sequence[i]}")
        print(f"detectedd: {detected}")
        assert detected == expected_outputs[i]
    
    dut.d.value = 0  
    # await RisingEdge(dut.clk) 
    await ClockCycles(dut.clk, 5)
    assert dut.detected.value == 0

def run_tests():
    factory = TestFactor(test_fetch_rom)
    factory.generate_tests()
 
if __name__ == "__main__":
    run_tests()
