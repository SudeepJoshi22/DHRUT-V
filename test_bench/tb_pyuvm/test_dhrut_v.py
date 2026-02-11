import pyuvm
from pyuvm import *
import os

from cocotb.triggers import RisingEdge

from .env import Env

@pyuvm.test()
class DhrutVTest(uvm_test):
    """
    Single test with PASS/FAIL mechanism
    """
    def build_phase(self):
        
        #self.logger.info(f"DEBUG: cocotb.plusargs = {cocotb.plusargs}")
        #self.logger.info(f"DEBUG: cocotb.argv = {cocotb.argv}")
        #self.logger.info(f"DEBUG: os.environ keys with CYCLE = {[k for k in os.environ if 'CYCLE' in k]}")  # Optional debug
        
        # Parse CYCLE_TIMEOUT from environment variable
        try:
            cycle_timeout = int(os.environ["CYCLE_TIMEOUT"])
            print(f"[DEBUG] got cycle_timeout = {cycle_timeout}")
            ConfigDB().set(None, "*", "CYCLE_TIMEOUT", cycle_timeout)
            self.logger.info(f"✓ Set CYCLE_TIMEOUT={cycle_timeout}")
        except KeyError:
            default = 100
            ConfigDB().set(None, "*", "CYCLE_TIMEOUT", default)
            self.logger.info(f"⚠ Default CYCLE_TIMEOUT={default}")

        self.env = Env("env", self)

    async def run_phase(self):
        self.raise_objection()
        
        cycle_timeout = ConfigDB().get(None, "", "CYCLE_TIMEOUT", 100)
        
        self.logger.info(f"Running for {cycle_timeout} cycles")
        
        for _ in range(cycle_timeout):
            await RisingEdge(cocotb.top.clk)
        
        self.drop_objection()

