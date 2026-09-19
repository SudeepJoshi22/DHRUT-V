from pyuvm import uvm_agent
from .cpu_monitor import CpuMonitor
from .cpu_tracer import CpuTracer
import os

class CpuMonitorAgent(uvm_agent):
    def build_phase(self):
        # These observers are passive and expensive (many VPI reads per cycle).
        # Benchmark checks need the DMEM monitor/tohost scoreboard, which remain
        # active in Env, but can skip pipeline and retired-instruction traces.
        if os.environ.get("CPU_TRACE", "1") == "0":
            return
        self.monitor = CpuMonitor.create("monitor", self)
        self.tracer = CpuTracer.create("tracer", self)

    def connect_phase(self):
        # Nothing to connect yet — monitor/tracer are passive
        pass
