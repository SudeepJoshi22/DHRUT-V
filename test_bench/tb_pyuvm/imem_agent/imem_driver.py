# test_bench/tb_pyuvm/agents/imem_agent/imem_driver.py
import logging
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
        self.logger = logging.getLogger("my_cpu_tb." + self.get_name())
        self.imem_if = cocotb.top.imem_if

        self.mem = {}
        hex_file = os.getenv("TEST_HEX")
        self.mem = self.load_verilog_hex(hex_file)
        self.logger.info("IMEM contents:")
        for a, w in self.mem.items():
            self.logger.info(f"0x{a:08x}: 0x{w:08x}")

    async def run_phase(self):

        # Default signal values


        while True:
            await RisingEdge(self.imem_if.clk)
            
            self.imem_if.s_ready.value = 0
            self.imem_if.s_rdata.value = 0
            abort = False
            if self.imem_if.m_valid.value:
                addr = self.imem_if.m_addr.value.to_unsigned()
                # 64-bit fetch: the core requests an 8-byte aligned block and
                # expects both of its instructions back - the word at the
                # aligned address in [31:0], the next word in [63:32].
                block_addr = addr & ~7
                w0 = self.mem.get(block_addr, 0x00000013)      # default NOP if not found
                w1 = self.mem.get(block_addr + 4, 0x00000013)
                instr = (w1 << 32) | w0

                # MEM_STALL_MODE=zero disables injected fetch latency, to
                # measure the core's intrinsic IPC without synthetic memory
                # stalls dominating. Default (random) keeps the randomized
                # timing that shakes out handshake/flush bugs.
                stall_enabled = os.getenv("MEM_STALL_MODE", "random") != "zero"

                if stall_enabled and random.random() < 0.4:
                    stall_cycles = random.randint(1, 2)  # 1 or 2 cycles of stall
                    self.logger.debug(f"IMem introducing {stall_cycles} stall cycle(s)")

                    self.imem_if.s_ready.value = 0
                    for _ in range(stall_cycles):
                        if self.imem_if.m_flush.value:
                            self.logger.debug(f"IMEM got flush from the Core, Aborting this transaction!")
                            abort = True
                            break
                        await RisingEdge(self.imem_if.clk)

                # Drive response.
                #
                # Only answer if the core still wants THIS address. Stalling
                # above advances time, during which a mispredict flush can
                # redirect the core: m_flush is a single-cycle pulse, so the
                # loop's pre-await check can miss it entirely. Responding
                # anyway hands back data fetched for the old address while
                # the core has already moved pc_q to a new block, and the
                # core then pairs the NEW pc with the OLD instruction --
                # silent instruction corruption, and exactly the failure
                # that broke Dhrystone once 64-bit fetch made speculative
                # wrong-path fetches (and therefore flushes) common.
                if not abort:
                    still_requesting = bool(self.imem_if.m_valid.value)
                    cur_addr = (self.imem_if.m_addr.value.to_unsigned()
                                if still_requesting else None)
                    if (still_requesting
                            and cur_addr == addr
                            and not self.imem_if.m_flush.value):
                        self.imem_if.s_rdata.value = instr
                        self.imem_if.s_ready.value = 1
                    else:
                        self.logger.debug(
                            f"IMEM dropping stale response for 0x{addr:08x} "
                            f"(core now at {'0x%08x' % cur_addr if cur_addr is not None else 'idle'})"
                        )
