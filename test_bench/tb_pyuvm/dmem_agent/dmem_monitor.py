# test_bench/tb_pyuvm/agents/dmem_agent/dmem_monitor.py
import cocotb
from cocotb.triggers import RisingEdge, ReadOnly
from pyuvm import uvm_monitor, uvm_analysis_port

class DMemMonitor(uvm_monitor):
    # Set it here (EDIT THIS):
    TOHOST_ADDR = 0x80001000

    def build_phase(self):
        self.dmem_if = cocotb.top.dmem_if

        self.ap = uvm_analysis_port("ap", self)               # all transactions
        self.tohost_ap = uvm_analysis_port("tohost_ap", self) # tohost “event” channel

        self.shadow = {}  # for merging partial writes via wstrb

    async def run_phase(self):
        while True:
            await RisingEdge(self.dmem_if.clk)
            await ReadOnly()

            if not int(self.dmem_if.m_valid.value):
                continue
            if not int(self.dmem_if.s_ready.value):
                continue

            addr = int(self.dmem_if.m_addr.value)
            aligned = addr & ~3

            wstrb = int(self.dmem_if.m_wstrb.value)
            is_write = (wstrb != 0)

            if is_write:
                wdata = int(self.dmem_if.m_wdata.value)

                old_word = self.shadow.get(aligned, 0)
                new_word = old_word
                for i in range(4):
                    if (wstrb >> i) & 1:
                        byte = (wdata >> (8 * i)) & 0xFF
                        new_word = (new_word & ~(0xFF << (8 * i))) | (byte << (8 * i))
                self.shadow[aligned] = new_word

                self.logger.info(
                    f"DMEM WRITE addr=0x{aligned:08x} wdata=0x{wdata:08x} "
                    f"wstrb=0x{wstrb:x} merged=0x{new_word:08x}"
                )

                self.ap.write(("W", aligned, wdata, wstrb, new_word))

                if aligned == self.TOHOST_ADDR:
                    self.logger.warning(f"TOHOST WRITE value=0x{new_word:08x}")
                    self.tohost_ap.write(new_word)

            else:
                rdata = int(self.dmem_if.s_rdata.value)
                self.shadow[aligned] = rdata

                self.logger.info(f"DMEM READ  addr=0x{aligned:08x} rdata=0x{rdata:08x}")
                self.ap.write(("R", aligned, rdata))
