from pyuvm import uvm_agent
from pyuvm import ConfigDB
from .imem_driver import IMemDriver
#from .imem_monitor import IMemMonitor
#from .imem_sequencer import IMemSequencer

class IMemAgent(uvm_agent):

    def build_phase(self):
        self.driver = IMemDriver.create("imem_driver", self)
        #self.monitor = imem_monitor.create("imem_monitor", self)
        #self.sequencer = imem_sequencer.create("imem_sequencer", self)
        
        #ConfigDB().set(None, "*", "imem_sequencer", self.sequencer)

    def connect_phase(self):
        pass
        #self.monitor.addr_ph_port.connect(self.sequencer.addr_port.analysis_export)
        #self.driver.seq_item_port.connect(self.sequencer.seq_item_export)
    
    def reset(self):
        pass
        #self.sequencer.reset()
