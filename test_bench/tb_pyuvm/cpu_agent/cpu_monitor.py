import logging
from pyuvm import uvm_sequence_item, uvm_monitor, uvm_analysis_port
import cocotb
from cocotb.triggers import RisingEdge, FallingEdge
from cocotb.triggers import Timer

# ───────────────────────────────────────────────
# Monitor Item – Now includes both IF and Decode signals
# ───────────────────────────────────────────────
class CpuMonitorItem(uvm_sequence_item):
    def __init__(self, name="CpuMonitorItem"):
        super().__init__(name)
        self.timestamp     = 0.0

        self.if_id_valid   = False     # ← must match assignment
        self.if_id_pc      = 0
        self.if_id_instr   = 0

        self.i_stall       = False
        self.i_flush       = False

        self.id_if_stall   = False

        self.o_dec_valid   = False
        self.o_dec_pc      = 0

        self.uop_valid     = False
        self.uop_opcode    = 0
        self.uop_rd        = 0
        self.uop_uses_rs1  = False
        self.uop_uses_rs2  = False
        self.uop_writes_rd = False

    def __str__(self):
        s = f"@{self.timestamp:6.1f}ns | "
    
        # FETCH (IF → ID pipeline register)
        s += "[FETCH] "
        s += f"valid={int(self.if_id_valid):1} "
        s += f"PC=0x{self.if_id_pc:08x} "
        s += f"instr=0x{self.if_id_instr:08x} "
        s += f"stall={int(self.i_stall):1} "
        s += f"flush={int(self.i_flush):1} "
        s += f"stall_IF={int(self.id_if_stall):1} | "
    
        # DECODE (outputs to EX)
        s += "[DECODE] "
        s += f"valid={int(self.o_dec_valid):1} "
        if self.o_dec_valid:
            s += f"PC=0x{self.o_dec_pc:08x} "
            s += f"uop_valid={int(self.uop_valid):1} "
            s += f"opcode=0x{self.uop_opcode:02x} "
            s += f"rd=x{self.uop_rd:02d} "
            s += f"rs1=x{self.uop_rs1:02d} "
            s += f"rs2=x{self.uop_rs2:02d} "
            s += f"wr={int(self.uop_writes_rd):1} "
            s += f"imm={hex(self.uop_imm)}"
        else:
            s += "(idle)"
    
        return s

# ───────────────────────────────────────────────
# CPU Monitor – Observes both IF and Decode stages
# ───────────────────────────────────────────────
class CpuMonitor(uvm_monitor):
    def __init__(self, name, parent):
        super().__init__(name, parent)
        self.logger = logging.getLogger("my_cpu_tb." + self.get_name())
        self.ap = uvm_analysis_port("ap", self)

    def build_phase(self):
        self.dut = cocotb.top

    async def run_phase(self):
        # Lazily get DUT only when run_phase starts (safe!)
        if self.dut is None:
            self.dut = cocotb.top
            if self.dut is None:
                self.logger.critical("Failed to get cocotb.top in run_phase!")
                return

        self.logger.info("Monitor now observing DUT successfully!")

        # Debug: print all top-level attributes (only once)
        if not hasattr(self, '_printed_attrs'):
            self.logger.info("Available top-level signals in dut:")
            for attr in dir(self.dut):
                if not attr.startswith('_'):
                    self.logger.info(f"  - {attr}")
            self._printed_attrs = True

        item = CpuMonitorItem()
        
        while True:
            await RisingEdge(self.dut.clk)
            #await FallingEdge(self.dut.clk)

            #await Timer(1, unit="step")
            
            #self.logger.info(f"Raw if_id_valid = {self.dut.if_id_valid.value}")
            #self.logger.info(f"Raw o_dec_valid = {self.dut.id_ex_valid.value}")
            
            item.timestamp = cocotb.utils.get_sim_time(unit="ns")

            # ── IF → ID pipeline register (internal signals) ──
            item.if_id_valid = bool(self.dut.if_id_valid.value)
            item.if_id_pc    = int(self.dut.if_id_pc.value)
            item.if_id_instr = int(self.dut.if_id_instr.value)

            # ── ID → IF stall back-pressure ──
            item.id_if_stall = bool(self.dut.id_if_stall.value)

            # ── Decode outputs to EX ──
            item.o_dec_valid = bool(self.dut.id_ex_valid.value)
            item.o_dec_pc    = int(self.dut.id_ex_pc.value)

            # ── uop contents (only when decode valid) ──
            uop_raw = self.dut.id_ex_uop.value  # get the full 69-bit LogicArray

            # Extract bits (MSB=68, LSB=0)
            item.uop_valid      = bool(uop_raw[68])
            item.uop_opcode     = int(uop_raw[67:61])     # 7 bits
            item.uop_alu_op   = int(uop_raw[60:51])     # 10 bits - optional
            item.uop_rd         = int(uop_raw[40:36])     # 5 bits
            item.uop_uses_rs1   = bool(uop_raw[3])
            item.uop_uses_rs2   = bool(uop_raw[2])
            item.uop_writes_rd  = bool(uop_raw[1])
            item.uop_rs1      = int(uop_raw[50:46])
            item.uop_rs2      = int(uop_raw[45:41])
            item.uop_imm      = int(uop_raw[35:4])

            if item.if_id_valid or item.o_dec_valid:
                self.logger.info(str(item))

            # ── Broadcast for future scoreboard/coverage ──
            self.ap.write(item)
