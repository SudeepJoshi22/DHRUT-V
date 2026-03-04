import logging
import os
import cocotb
from cocotb.triggers import Timer

from pyuvm import (
    uvm_component,
    uvm_tlm_analysis_fifo,
    uvm_get_port,
    ConfigDB
)

class Scoreboard(uvm_component):
    def __init__(self, name, parent):
        super().__init__(name, parent)
        self.memwr_fifo = None
        self.memwr_export = None
        self.memwr_get_port = None
        self.mem = {}

    def load_verilog_hex(self, path):
        """
        Load a Verilog-style @address hex file into the byte-oriented memory model.
        """
        if not path or not os.path.exists(path):
            return

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
                            self.mem[addr] = int(b, 16)
                            addr += 1
        except Exception as e:
            self.logger.warning(f"Failed to load hex file {path} into scoreboard: {e}")

    def build_phase(self):
        super().build_phase()
        self.logger = logging.getLogger("my_cpu_tb." + self.get_name())

        # Pre-load memory from HEX file to capture initial values (required for some signature lines)
        hex_file = os.getenv("TEST_HEX")
        if hex_file:
            self.load_verilog_hex(hex_file)
            self.logger.info(f"Scoreboard pre-loaded {len(self.mem)} bytes from {hex_file}")

        # tohost (PASS/FAIL)
        self.tohost_fifo = uvm_tlm_analysis_fifo("tohost_fifo", self)
        self.tohost_export = self.tohost_fifo.analysis_export
        self.tohost_get_port = uvm_get_port("tohost_get_port", self)
        
        # Get the end_event from ConfigDB
        self.end_event = ConfigDB().get(self, "", "end_event")

    def connect_phase(self):
        super().connect_phase()
        self.tohost_get_port.connect(self.tohost_fifo.get_export)
        if self.memwr_get_port is not None:
            self.memwr_get_port.connect(self.memwr_fifo.get_export)

    def enable_memwrite_capture(self):
        """Call this from Env only if DMemMonitor provides memwr_ap."""
        if self.memwr_fifo is not None:
            return
        self.memwr_fifo = uvm_tlm_analysis_fifo("memwr_fifo", self)
        self.memwr_export = self.memwr_fifo.analysis_export
        self.memwr_get_port = uvm_get_port("memwr_get_port", self)

    async def run_phase(self):
        async def collect_mem_writes():
            # Should never be started unless capture is enabled, but keep it safe.
            if self.memwr_get_port is None:
                return
            
            # Cache sig range for fast check in loop
            begin_s = os.environ.get("SIG_BEGIN")
            end_s = os.environ.get("SIG_END")
            sig_begin = int(begin_s, 16) if begin_s else 0
            sig_end = int(end_s, 16) if end_s else 0

            while True:
                txn = await self.memwr_get_port.get()
                addr = int(txn.addr)
                data = int(txn.data)
                size = int(txn.size)
                wstrb = int(txn.wstrb)

                self.logger.debug(f"Received MemWrite at 0x{addr:08x}, wstrb=0x{wstrb:x}")

                for i in range(size):
                    if (wstrb >> i) & 1:
                        byte = (data >> (8 * i)) & 0xFF
                        self.mem[addr + i] = byte
                        if sig_begin <= (addr + i) < sig_end:
                            # Use debug to keep simulation log cleaner
                            self.logger.debug(f"Signature updated at 0x{(addr+i):08x} with 0x{byte:02x}")

        async def watch_tohost():
            while True:
                val = int(await self.tohost_get_port.get())

                # Ignore non-terminating writes
                if (val & 0x1) == 0:
                    continue

                exit_code = (val >> 1)
                if exit_code == 0:
                    self.logger.info(f"PASS: tohost=0x{val:08x}")
                    if self.end_event and not self.end_event.is_set():
                        self.end_event.set()
                    return
                else:
                    msg = f"FAIL: tohost=0x{val:08x}, exit_code={exit_code}"
                    self.logger.error(msg)
                    if self.end_event and not self.end_event.is_set():
                        self.end_event.set()
                    assert False, msg

        # Only start the collector if enabled
        if self.memwr_get_port is not None:
            cocotb.start_soon(collect_mem_writes())

        await watch_tohost()

    def final_phase(self):
        super().final_phase()

        sig_path = os.environ.get("SIGNATURE_FILE")
        begin_s  = os.environ.get("SIG_BEGIN")
        end_s    = os.environ.get("SIG_END")

        if not sig_path:
            return

        self.logger.debug(f"Signature requested: {sig_path}, begin={begin_s}, end={end_s}")

        if not begin_s or not end_s:
            self.logger.warning("SIG_BEGIN/SIG_END not set; creating empty signature file.")
            open(sig_path, "w").close()
            return

        begin = int(begin_s, 16)
        end   = int(end_s, 16)
        self.logger.info(f"Dumping signature from 0x{begin:08x} to 0x{end:08x} ({ (end-begin)//4 } words)")

        # Dump 32-bit words, low addr to high, one per line
        with open(sig_path, "w") as f:
            for a in range(begin, end, 4):
                b0 = self.mem.get(a + 0, 0)
                b1 = self.mem.get(a + 1, 0)
                b2 = self.mem.get(a + 2, 0)
                b3 = self.mem.get(a + 3, 0)
                word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
                f.write(f"{word:08x}\n")

        self.logger.info(f"Successfully wrote signature: {sig_path}")
