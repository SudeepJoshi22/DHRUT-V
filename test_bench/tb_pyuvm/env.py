from pyuvm import uvm_env

import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock

from .imem_agent.imem_agent import IMemAgent

class Env(uvm_env):
    def build_phase(self):
        super().build_phase()

        self.imem_agent = IMemAgent("imem_agent", self)

    def connect_phase(self):
        super().connect_phase()  # Optional but good practice

        # Future connections go here:
        # Example: connect monitor to scoreboard
        # self.imem_agent.monitor.ap.connect(self.scoreboard.imem_fifo.analysis_export)

        # Example: connect control signals to other agents
        # self.control_agent.ap.connect(self.imem_agent.driver.control_imp)

        pass  # Nothing to connect yet — just imem agent is active
