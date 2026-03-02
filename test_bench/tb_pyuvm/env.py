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
        
        # Enable memwrite capture in build phase so ports exist during connect phase
        self.scoreboard.enable_memwrite_capture()

    def connect_phase(self):
        super().connect_phase()
    
        # Always connect tohost (PASS/FAIL)
        self.dmem_agent.monitor.tohost_ap.connect(self.scoreboard.tohost_export)
    
        # Connect mem write channel (signature support)
        mon = self.dmem_agent.monitor
        if hasattr(mon, "memwr_ap"):
            mon.memwr_ap.connect(self.scoreboard.memwr_export)
        else:
            self.logger.warning("DMemMonitor has no memwr_ap; signature dump will be empty/disabled.")
