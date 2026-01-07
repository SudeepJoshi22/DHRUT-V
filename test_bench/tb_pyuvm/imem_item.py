from pyuvm import uvm_sequence_item

class ImemItem(uvm_sequence_item):
    def __init__(self, addr=0, data=0):
        super().__init__("imem_item")
        self.addr = addr
        self.data = data
