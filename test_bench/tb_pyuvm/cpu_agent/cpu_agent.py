from pyuvm import uvm_agent
from .cpu_monitor import CpuMonitor
from .cpu_tracer import CpuTracer

class CpuMonitorAgent(uvm_agent):
    def build_phase(self):
        self.monitor = CpuMonitor.create("monitor", self)
        self.tracer = CpuTracer.create("tracer", self)

    def connect_phase(self):
        # Nothing to connect yet — monitor/tracer are passive
        pass
