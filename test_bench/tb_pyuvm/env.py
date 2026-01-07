from pyuvm import uvm_env

import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

from .imem_agent import *

class IfEnv(uvm_env):

    def build_phase(self):
        # CLOCK MUST EXIST HERE (like ALU)
        self.clk = Clock(cocotb.top.clk, 10, "ns")
        cocotb.start_soon(self.clk.start())

        # AGENT CREATION (this was missing)
        self.imem_agent = ImemAgent(
            "imem_agent",
            self,
            cocotb.top.imem_if
        )

    async def start_of_simulation_phase(self):
        dut = cocotb.top
        dut.rst_n.value = 0
        for _ in range(5):
            await RisingEdge(dut.clk)
        dut.rst_n.value = 1
