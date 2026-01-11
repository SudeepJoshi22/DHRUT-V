from pyuvm import uvm_agent
from .cpu_monitor import CpuMonitor

class CpuMonitorAgent(uvm_agent):
    def build_phase(self):
        self.monitor = CpuMonitor.create("monitor", self)

    def connect_phase(self):
        # Nothing to connect yet — monitor is passive
        pass
