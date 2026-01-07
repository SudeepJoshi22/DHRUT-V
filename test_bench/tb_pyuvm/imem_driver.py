import random
from cocotb.triggers import RisingEdge
from pyuvm import uvm_driver

class ImemDriver(uvm_driver):

    def __init__(self, name, parent, vif):
        super().__init__(name, parent)
        self.vif = vif

        # Instruction memory image
        self.mem = {
            0x00000000: 0x00500093,  # addi x1, x0, 5
            0x00000004: 0x00308113,  # addi x2, x1, 3
            0x00000008: 0x00000013,  # nop
        }

    async def run_phase(self):
        self.vif.ready.value = 0
        self.vif.rdata.value = 0

        while True:
            await RisingEdge(self.vif.clk)

            if self.vif.valid.value:
                addr = int(self.vif.addr.value)

                # Optional random stall
                stall_cycles = random.randint(0, 2)
                for _ in range(stall_cycles):
                    await RisingEdge(self.vif.clk)

                instr = self.mem.get(addr, 0x00000013)

                self.vif.rdata.value = instr
                self.vif.ready.value = 1

                await RisingEdge(self.vif.clk)

                self.vif.ready.value = 0
