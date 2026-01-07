import pyuvm
from pyuvm import *

from cocotb.triggers import RisingEdge

from .env import IfEnv

@pyuvm.test()
class IfSmokeTest(uvm_test):

    def build_phase(self):
        self.env = IfEnv("env", self)

    async def run_phase(self):
        self.raise_objection()

        # Let the environment run for N cycles
        for _ in range(100):
            await RisingEdge(cocotb.top.clk)

        self.drop_objection()
