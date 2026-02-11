from pyuvm import uvm_env
from .scoreboard import Scoreboard

from .imem_agent.imem_agent import IMemAgent
from .cpu_agent.cpu_agent import CpuMonitorAgent
from .dmem_agent.dmem_agent import DMemAgent

class Env(uvm_env):
    def build_phase(self):
        super().build_phase()

        self.imem_agent = IMemAgent("imem_agent", self)
        self.cpu_agent  = CpuMonitorAgent("cpu_agent", self)
        self.dmem_agent = DMemAgent("dmem_agent", self)

        self.scoreboard = Scoreboard("scoreboard", self)

    def connect_phase(self):
        super().connect_phase()

        # DMEM monitor -> scoreboard (tohost only)
        self.dmem_agent.monitor.tohost_ap.connect(self.scoreboard.tohost_export)  # [web:28]
