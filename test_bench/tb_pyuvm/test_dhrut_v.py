import pyuvm
from pyuvm import *
import os
import logging

from cocotb.triggers import RisingEdge, Event
import cocotb

from .env import Env

@pyuvm.test()
class DhrutVTest(uvm_test):
    """
    Single test with PASS/FAIL mechanism
    """
    def build_phase(self):
        super().build_phase()
        self.env = Env("env", self)
        
        # Create a standard cocotb event
        self.end_event = Event("end_event")
        ConfigDB().set(None, "*", "end_event", self.end_event)

    async def run_phase(self):
        self.raise_objection()
        
        # Get timeout from env var
        try:
            cycle_timeout = int(os.environ.get("CYCLE_TIMEOUT", "100000"))
        except:
            cycle_timeout = 100000
            
        self.logger.info(f"Running with max timeout of {cycle_timeout} cycles")
        
        # Start a timeout watchdog
        async def timeout_watcher():
            for _ in range(cycle_timeout):
                await RisingEdge(cocotb.top.clk)
            
            if not self.end_event.is_set():
                self.logger.error("WATCHDOG TIMEOUT reached!")
                self.end_event.set()

        cocotb.start_soon(timeout_watcher())

        # Wait for the event (set by either scoreboard or watchdog)
        await self.end_event.wait()
        self.logger.info(f"Test termination triggered at {cocotb.utils.get_sim_time(unit='ns')}ns")
        
        self.drop_objection()
