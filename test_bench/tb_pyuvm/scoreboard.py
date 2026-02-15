import os
import cocotb
from cocotb.triggers import Timer

from pyuvm import (
    uvm_component,
    uvm_tlm_analysis_fifo,
    uvm_get_port,
)

class Scoreboard(uvm_component):
    def build_phase(self):
        super().build_phase()

        # tohost (PASS/FAIL)
        self.tohost_fifo = uvm_tlm_analysis_fifo("tohost_fifo", self)
        self.tohost_export = self.tohost_fifo.analysis_export
        self.tohost_get_port = uvm_get_port("tohost_get_port", self)

        # Memory model (byte-addressed) for signature dump
        self.mem = {}

        # Optional mem-write capture plumbing (disabled by default)
        self.memwr_fifo = None
        self.memwr_export = None
        self.memwr_get_port = None

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
            while True:
                txn = await self.memwr_get_port.get()

                # Adapt these field names to your txn object
                addr = int(txn.addr)
                data = int(txn.data)
                size = int(txn.size)
                wstrb = int(txn.wstrb)

                for i in range(size):
                    if (wstrb >> i) & 1:
                        self.mem[addr + i] = (data >> (8 * i)) & 0xFF

        async def watch_tohost():
            while True:
                val = int(await self.tohost_get_port.get())

                # Ignore non-terminating writes
                if (val & 0x1) == 0:
                    continue

                exit_code = (val >> 1)
                if exit_code == 0:
                    self.logger.info(f"PASS: tohost=0x{val:08x}")
                    cocotb.pass_test(f"PASS: tohost=0x{val:08x}")
                    return
                else:
                    msg = f"FAIL: tohost=0x{val:08x}, exit_code={exit_code}"
                    self.logger.error(msg)
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

        print(f"sig being: {hex(begin_s)}")
        print(f"sig end:   {hex(end_s)}")

        if not sig_path:
            # Not running under RISCOF (or not configured). Nothing to do.
            return

        # If we can't compute a range, still create an empty file so RISCOF doesn't fail on missing file.
        if not begin_s or not end_s:
            self.logger.warning("SIG_BEGIN/SIG_END not set; creating empty signature file.")
            open(sig_path, "w").close()
            return

        begin = int(begin_s, 16)
        end   = int(end_s, 16)

        if end <= begin or ((end - begin) % 4) != 0:
            self.logger.warning(f"Bad signature range begin={begin_s} end={end_s}; creating empty signature file.")
            open(sig_path, "w").close()
            return

        # If you didn't enable mem-write capture, you can't produce correct signature contents.
        if self.memwr_get_port is None:
            self.logger.warning("Mem-write capture not enabled; creating empty signature file.")
            open(sig_path, "w").close()
            return

        # Dump 32-bit words, low addr to high, one per line
        with open(sig_path, "w") as f:
            for a in range(begin, end, 4):
                b0 = self.mem.get(a + 0, 0)
                b1 = self.mem.get(a + 1, 0)
                b2 = self.mem.get(a + 2, 0)
                b3 = self.mem.get(a + 3, 0)
                word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
                f.write(f"{word:08x}\n")

        self.logger.info(f"Wrote signature: {sig_path}")
