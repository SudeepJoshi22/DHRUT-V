import pyuvm
from pyuvm import *

from cocotb.triggers import RisingEdge

from .env import Env

@pyuvm.test()
class IFBringUpTest(uvm_test):
    """
    Bring-up test for IF Stage
    """
    def build_phase(self):
        self.env = Env("env", self)

    async def run_phase(self):
        self.raise_objection()

        # Let the environment run for N cycles
        for _ in range(100):
            await RisingEdge(cocotb.top.clk)

        self.drop_objection()
