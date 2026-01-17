# test_bench/tb_pyuvm/agents/dmem_agent/dmem_driver.py
import random
import cocotb
import os

from cocotb.triggers import RisingEdge
from pyuvm import uvm_driver

class DMemDriver(uvm_driver):
    """
    Simple DMEM slave:
    - Preloaded memory from TEST_HEX (same format as IMEM).
    - Handles word-aligned loads/stores.
    - Random response stalls (0–2 cycles).
    """

    def load_verilog_hex(self, path):
        # Same helper as IMemDriver, reused for data memory
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

        # Pack bytes → 32‑bit words
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
        # Get the DMEM interface from top (match your DUT)
        self.dmem_if = cocotb.top.dmem_if

        # Initialize backing store from same TEST_HEX (or a separate env var)
        hex_file = os.getenv("TEST_HEX")
        self.mem = self.load_verilog_hex(hex_file) if hex_file else {}

        self.logger.info("DMEM initial contents:")
        for a, w in self.mem.items():
            self.logger.info(f"0x{a:08x}: 0x{w:08x}")

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

            addr = self.dmem_if.m_addr.value.to_unsigned()
            aligned_addr = addr & ~3

            is_write = int(self.dmem_if.m_wstrb.value) != 0

            # Optional random stall (like IMEM)
            if random.random() < 0.5:
                stall_cycles = random.randint(1, 2)
                self.logger.debug(f"DMem introducing {stall_cycles} stall cycle(s)")
                self.dmem_if.s_ready.value = 0
                for _ in range(stall_cycles):
                    await RisingEdge(self.dmem_if.clk)

            if is_write:
                # Write: apply byte enables into backing store
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
                self.logger.debug(
                    f"DMEM WRITE addr=0x{aligned_addr:08x}, "
                    f"wdata=0x{wdata:08x}, wstrb=0x{wstrb:x}, "
                    f"new_word=0x{new_word:08x}"
                )

                # For a pure write, rdata is typically don't‑care
                self.dmem_if.s_rdata.value = 0

            else:
                # Read: fetch word, default to 0
                rdata = self.mem.get(aligned_addr, 0)
                self.dmem_if.s_rdata.value = rdata
                self.logger.debug(
                    f"DMEM READ addr=0x{aligned_addr:08x}, rdata=0x{rdata:08x}"
                )

            # Complete bus handshake
            self.dmem_if.s_ready.value = 1

