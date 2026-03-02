# test_bench/tb_pyuvm/agents/dmem_agent/dmem_monitor.py
import logging
import cocotb
import os
import subprocess
from cocotb.triggers import RisingEdge, ReadOnly
from pyuvm import uvm_monitor, uvm_analysis_port

class MemWrite:
    def __init__(self, addr, data, wstrb, size=4):
        self.addr = addr
        self.data = data
        self.wstrb = wstrb
        self.size = size

class DMemMonitor(uvm_monitor):
    def build_phase(self):
        self.logger = logging.getLogger("my_cpu_tb." + self.get_name())
        self.dmem_if = cocotb.top.dmem_if

        # Dynamically determine TOHOST_ADDR
        self.tohost_addr = self._get_tohost_addr()
        self.logger.info(f"Monitoring tohost at 0x{self.tohost_addr:08x}")

        self.ap = uvm_analysis_port("ap", self)               # all transactions
        self.memwr_ap = uvm_analysis_port("memwr_ap", self)   # only writes (for signature)
        self.tohost_ap = uvm_analysis_port("tohost_ap", self) # tohost “event” channel

        self.shadow = {}  # for merging partial writes via wstrb

    def _get_tohost_addr(self):
        """Try to find tohost address from environment or ELF."""
        # 1. Check environment variable (set by riscof plugin)
        env_addr = os.environ.get("TOHOST_ADDR")
        if env_addr:
            try:
                return int(env_addr, 16) if env_addr.startswith("0x") else int(env_addr)
            except ValueError:
                pass

        # 2. Try to extract from ELF if available
        elf_path = os.environ.get("TEST_ELF")
        if elf_path and os.path.exists(elf_path):
            try:
                # Use nm to find tohost symbol
                cmd = f"riscv64-unknown-elf-nm -n {elf_path} | awk '$3==\"tohost\" {{print $1}}'"
                addr_str = subprocess.check_output(cmd, shell=True).decode().strip()
                if addr_str:
                    return int(addr_str, 16)
            except Exception as e:
                self.logger.debug(f"Failed to extract tohost from ELF: {e}")

        # 3. Fallback default
        return 0x80001000

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

                # Broadcast to generic AP
                self.ap.write(("W", aligned, wdata, wstrb, new_word))
                
                # Broadcast to signature AP
                self.memwr_ap.write(MemWrite(aligned, wdata, wstrb))

                if aligned == self.tohost_addr:
                    self.logger.info(f"TOHOST WRITE value=0x{new_word:08x}")
                    self.tohost_ap.write(new_word)

            else:
                rdata = int(self.dmem_if.s_rdata.value)
                self.shadow[aligned] = rdata

                self.logger.info(f"DMEM READ  addr=0x{aligned:08x} rdata=0x{rdata:08x}")
                self.ap.write(("R", aligned, rdata))
