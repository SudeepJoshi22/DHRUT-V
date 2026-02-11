import cocotb
from pyuvm import uvm_component, uvm_tlm_analysis_fifo, uvm_get_port

class Scoreboard(uvm_component):
    def build_phase(self):
        self.tohost_fifo = uvm_tlm_analysis_fifo("tohost_fifo", self)
        self.tohost_export = self.tohost_fifo.analysis_export
        self.tohost_get_port = uvm_get_port("tohost_get_port", self)

    def connect_phase(self):
        self.tohost_get_port.connect(self.tohost_fifo.get_export)

    async def run_phase(self):
        while True:
            val = int(await self.tohost_get_port.get())

            # Ignore non-terminating writes
            if (val & 0x1) == 0:
                continue

            exit_code = (val >> 1)
            if exit_code == 0:
                self.logger.info(f"PASS: tohost=0x{val:08x}")
                cocotb.pass_test(f"PASS: tohost=0x{val:08x}")  # ends test as pass [page:0]
                return
            else:
                msg = f"FAIL: tohost=0x{val:08x}, exit_code={exit_code}"
                self.logger.error(msg)
                assert False, msg  # assert failure fails the test [page:0]
