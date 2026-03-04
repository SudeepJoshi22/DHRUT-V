# test_bench/tb_pyuvm/agents/dmem_agent/dmem_driver.py
import random
import cocotb
import os
import logging

from cocotb.triggers import RisingEdge
from pyuvm import uvm_driver

class DMemDriver(uvm_driver):
    """
    Simple DMEM slave:
    - Preloaded memory from TEST_HEX (same format as IMEM).
    - Handles word-aligned loads/stores.
    - Random response stalls (1–5 cycles).
    """

    def load_verilog_hex(self, path):
        """
        Load a Verilog-style @address hex file into a byte-oriented dictionary.
        Then pack it into 32-bit words for our backing store.
        """
        bytes_mem = {}
        addr = 0

        try:
            with open(path, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("//"):
                        continue

                    if line.startswith("@"):
                        addr = int(line[1:], 16)
                    else:
                        bytestr = line.split()
                        for b in bytestr:
                            bytes_mem[addr] = int(b, 16)
                            addr += 1
        except FileNotFoundError:
            self.logger.warning(f"Hex file {path} not found; memory starts empty.")
            return {}

        # Pack bytes into 32-bit little-endian words
        word_mem = {}
        if bytes_mem:
            # Find all 4-byte aligned addresses covered by the byte memory
            min_a = min(bytes_mem.keys()) & ~3
            max_a = max(bytes_mem.keys()) | 3
            
            for a in range(min_a, max_a + 1, 4):
                word = (
                    bytes_mem.get(a, 0)
                    | (bytes_mem.get(a + 1, 0) << 8)
                    | (bytes_mem.get(a + 2, 0) << 16)
                    | (bytes_mem.get(a + 3, 0) << 24)
                )
                if any(x in bytes_mem for x in range(a, a+4)):
                    word_mem[a] = word

        return word_mem

    def build_phase(self):
        # Use prefix-based logger
        self.logger = logging.getLogger("my_cpu_tb." + self.get_name())
        self.dmem_if = cocotb.top.dmem_if
        
        # Initialize memory once
        hex_file = os.getenv("TEST_HEX")
        if hex_file:
            self.mem = self.load_verilog_hex(hex_file)
            self.logger.info(f"DMEM preloaded from {hex_file} ({len(self.mem)} words)")
        else:
            self.mem = {}
            self.logger.info("DMEM initialized empty (no TEST_HEX)")

    async def run_phase(self):
        # Default bus values
        self.dmem_if.s_ready.value = 0
        self.dmem_if.s_rdata.value = 0

        while True:
            await RisingEdge(self.dmem_if.clk)

            if not self.dmem_if.m_valid.value:
                # No request this cycle
                self.dmem_if.s_ready.value = 0
                continue

            # Capture request signals
            try:
                addr = int(self.dmem_if.m_addr.value)
            except:
                addr = 0
                
            aligned_addr = addr & ~3
            is_write = (int(self.dmem_if.m_wstrb.value) != 0)

            # Random stall (1-5 cycles)
            stall_cycles = random.randint(1, 5)
            self.dmem_if.s_ready.value = 0
            for _ in range(stall_cycles):
                await RisingEdge(self.dmem_if.clk)

            if is_write:
                # Capture write data and strobes
                wdata = int(self.dmem_if.m_wdata.value)
                wstrb = int(self.dmem_if.m_wstrb.value)

                old_word = self.mem.get(aligned_addr, 0)
                new_word = old_word

                for i in range(4):
                    if (wstrb >> i) & 0x1:
                        byte = (wdata >> (8 * i)) & 0xFF
                        new_word &= ~(0xFF << (8 * i))
                        new_word |= byte << (8 * i)

                self.mem[aligned_addr] = new_word
                # Redundant prints silenced per user request
                # self.logger.info(...)
                self.dmem_if.s_rdata.value = 0
            else:
                # Read: fetch word, default to 0
                rdata = self.mem.get(aligned_addr, 0)
                self.dmem_if.s_rdata.value = rdata
                # self.logger.info(...)

            # Complete handshake
            self.dmem_if.s_ready.value = 1
            await RisingEdge(self.dmem_if.clk)
            self.dmem_if.s_ready.value = 0
