from pyuvm import uvm_agent
from .imem_driver import ImemDriver

class ImemAgent(uvm_agent):

    def __init__(self, name, parent, vif):
        super().__init__(name, parent)
        self.vif = vif

    def build_phase(self):
        self.driver = ImemDriver("driver", self, self.vif)
