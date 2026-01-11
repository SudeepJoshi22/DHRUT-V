# test_bench/tb_pyuvm/agents/imem_agent/imem_driver.py
import random
import cocotb
import pathlib
import os

from cocotb.triggers import RisingEdge
from pyuvm import uvm_driver

class IMemDriver(uvm_driver):
    """
    Simple pre-loaded IMem Slave Driver
    - Hard-coded instruction memory (like your old working version)
    - Random stalls (0-2 cycles)
    - Directly drives s_ready and s_rdata
    - No sequence loading needed for now
    """

    def load_verilog_hex(self,path):
        mem = {}
        addr = 0

        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue

                if line.startswith("@"):
                    addr = int(line[1:], 16)
                else:
                    bytestr = line.split()
                    for b in bytestr:
                        mem[addr] = int(b, 16)
                        addr += 1

        # Pack bytes → 32-bit words
        word_mem = {}
        for a in sorted(mem.keys()):
            if a % 4 == 0:
                word = (
                    mem.get(a, 0)
                    | (mem.get(a + 1, 0) << 8)
                    | (mem.get(a + 2, 0) << 16)
                    | (mem.get(a + 3, 0) << 24)
                )
                word_mem[a] = word

        return word_mem

    def build_phase(self):
        # Get the interface handle from ConfigDB (set in run_test.py)
        self.imem_if = cocotb.top.imem_if

        # Pre-coded instruction memory — exactly like your old driver
        '''
        self.mem = {
            0x00000000: 0x00500093,  # addi x1, x0, 5
            0x00000004: 0x00308113,  # addi x2, x1, 3
            0x00000008: 0x00000013,  # nop
            # You can add more later
        }
        '''
        self.mem = {}
        hex_file = os.getenv("TEST_HEX")
        self.mem = self.load_verilog_hex(hex_file)
        self.logger.info("IMEM contents:")
        for a, w in self.mem.items():
            self.logger.info(f"0x{a:08x}: 0x{w:08x}")

    async def run_phase(self):

        # Default signal values
        self.imem_if.s_ready.value = 0
        self.imem_if.s_rdata.value = 0

        while True:
            await RisingEdge(self.imem_if.clk)

            if self.imem_if.m_valid.value:
                addr = self.imem_if.m_addr.value.to_unsigned()
                aligned_addr = addr & ~3
                instr = self.mem.get(aligned_addr, 0x00000013)  # default NOP if not found

            # Rare latency: 90% chance of 0 stall, 10% chance of 1 or 2 stall cycles
            if random.random() < 0.1:
                stall_cycles = random.randint(1, 2)  # 1 or 2 cycles of stall
                self.logger.debug(f"IMem introducing {stall_cycles} stall cycle(s)")
                
                self.imem_if.s_ready.value = 0
                for _ in range(stall_cycles):
                    await RisingEdge(self.imem_if.clk)

            # Drive response
            self.imem_if.s_rdata.value = instr
            self.imem_if.s_ready.value = 1
