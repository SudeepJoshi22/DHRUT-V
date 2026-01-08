# test_bench/tb_pyuvm/agents/imem_agent/imem_driver.py
import random
import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import uvm_driver, ConfigDB

class IMemDriver(uvm_driver):
    """
    Simple pre-loaded IMem Slave Driver
    - Hard-coded instruction memory (like your old working version)
    - Random stalls (0-2 cycles)
    - Directly drives s_ready and s_rdata
    - No sequence loading needed for now
    """
    def build_phase(self):
        # Get the interface handle from ConfigDB (set in run_test.py)
        self.imem_if = cocotb.top.imem_if

        # Pre-coded instruction memory — exactly like your old driver
        self.mem = {
            0x00000000: 0x00500093,  # addi x1, x0, 5
            0x00000004: 0x00308113,  # addi x2, x1, 3
            0x00000008: 0x00000013,  # nop
            # You can add more later
        }

    async def run_phase(self):
        if self.imem_if is None:
            self.logger.critical("IMEM_IF not found in ConfigDB!")
            return

        # Default signal values
        self.imem_if.s_ready.value = 0
        self.imem_if.s_rdata.value = 0

        while True:
            await RisingEdge(self.imem_if.clk)

            # Default: not ready
            self.imem_if.s_ready.value = 0
            self.imem_if.s_rdata.value = 0

            if self.imem_if.m_valid.value:
                addr = self.imem_if.m_addr.value.integer
                aligned_addr = addr & ~3
                instr = self.mem.get(aligned_addr, 0x00000013)  # default NOP if not found

                # Random stall: 0 to 2 cycles (exactly like your old code)
                stall_cycles = random.randint(0, 2)
                for _ in range(stall_cycles):
                    await RisingEdge(self.imem_if.clk)

                # Drive response
                self.imem_if.s_rdata.value = instr
                self.imem_if.s_ready.value = 1

                # Hold ready for one cycle to complete handshake
                await RisingEdge(self.imem_if.clk)

                # Deassert ready
                self.imem_if.s_ready.value = 0
