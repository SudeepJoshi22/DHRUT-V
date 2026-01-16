# test_bench/tb_pyuvm/agents/dmem_agent/dmem_agent.py
from pyuvm import uvm_agent
from .dmem_driver import DMemDriver
# from .dmem_monitor import DMemMonitor
# from .dmem_sequencer import DMemSequencer
# from pyuvm import ConfigDB   # only if you decide to use a sequencer

class DMemAgent(uvm_agent):

    def build_phase(self):
        # Active agent with only a driver for now
        self.driver = DMemDriver.create("dmem_driver", self)

        # If you later add sequencer/monitor, uncomment and wire like IMemAgent
        # self.monitor = DMemMonitor.create("dmem_monitor", self)
        # self.sequencer = DMemSequencer.create("dmem_sequencer", self)
        # ConfigDB().set(None, "*", "dmem_sequencer", self.sequencer)

    def connect_phase(self):
        # When sequencer/monitor exist, connect TLM ports here
        # self.driver.seq_item_port.connect(self.sequencer.seq_item_export)
        # self.monitor.addr_ph_port.connect(self.sequencer.addr_port.analysis_export)
        pass

    def reset(self):
        # If you later add sequences, reset them here
        # self.sequencer.reset()
        pass
