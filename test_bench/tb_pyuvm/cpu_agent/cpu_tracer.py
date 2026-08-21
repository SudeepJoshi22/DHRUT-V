"""
cpu_tracer.py - Spike-style per-retired-instruction trace (cpu_trace.log)

Produces a two-line-per-retired-instruction trace matching the layout used
by Spike's --log-commits output (see tests/build/*.spike.log):

    core 0: 0x<pc8> (0x<instr8>) <mnemonic> <operands>
    core 0: 3 0x<pc8> (0x<instr8>) [x<rd> 0x<value8>] [mem 0x<addr8>]

The register-write field ([xN 0x...]) is present only when the instruction
actually writes a register; the memory field ([mem 0x...]) is present only
for loads/stores.

Why a software queue: this pipeline's uop_t (rtl/include/riscv_uop_pkg.sv)
does not carry the raw instruction word or PC past decode, so the raw
32-bit instruction has to be captured at IF (if_id_instr/if_id_pc) and
carried forward in software, keyed to the instruction that eventually
completes execution in ALU/LSU. The pipeline is single-issue and in-order,
and (per rtl/tb_top.sv) only IF/decode/issue are squashed on `mispredict`
-- ALU/LSU/RETIRE always run i_flush=1'b0, so once dispatched an
instruction always completes. That means "retirement" can be detected
directly off ALU.o_valid / LSU.o_valid (tb_top's alu_retire_valid /
lsu_valid) without waiting an extra cycle for the retire_wb_* registers,
and the associated PC/uop can be read straight from ALU.pc_q/uop_q or
LSU.pc_q/uop_q (already tapped by monitor_config.yaml's extraction blocks).

Flush handling: entries pushed at IF for instructions that are later
squashed in IF/decode/issue (before ever being dispatched to ALU/LSU) must
never produce a trace line. Rather than trying to replicate the exact
flush timing/depth, the queue is consumed by PC match: on every
ALU/LSU retirement event we pop from the front of the FIFO and, if its PC
doesn't match the retiring PC, we scan forward and silently drop any
stale (flushed) entries in front of the real match. This is robust to
repeated PCs (loops) because the queue is strictly in program order and we
always match the oldest still-queued entry.
"""

import logging
import os
from collections import deque

import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import uvm_component

DEFAULT_TRACE_FILE = "cpu_trace.log"

OPCODE_LOAD = 0x03
OPCODE_OP_IMM = 0x13
OPCODE_AUIPC = 0x17
OPCODE_STORE = 0x23
OPCODE_OP = 0x33
OPCODE_LUI = 0x37
OPCODE_BRANCH = 0x63
OPCODE_JALR = 0x67
OPCODE_JAL = 0x6F

ALU_OP_NAMES = {
    0x0: "add", 0x8: "sub",
    0x1: "sll", 0x2: "slt", 0x3: "sltu",
    0x4: "xor", 0x5: "srl", 0xD: "sra",
    0x6: "or", 0x7: "and",
}
BRANCH_NAMES = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
LOAD_NAMES = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
STORE_NAMES = {0: "sb", 1: "sh", 2: "sw"}


def _simm(imm):
    """imm fields are already sign-extended 32-bit values; render signed for readability."""
    imm &= 0xFFFFFFFF
    return imm - (1 << 32) if imm & 0x80000000 else imm


def disassemble(opcode, funct3, alu_op, is_immediate, is_branch, is_jump,
                 is_load, is_store, rd, rs1, rs2, imm):
    """Reconstruct a mnemonic + operand string from decoded uop fields (RV32I)."""
    simm = _simm(imm)

    if is_load:
        name = LOAD_NAMES.get(funct3, f"l?{funct3}")
        return f"{name} x{rd}, {simm}(x{rs1})"
    if is_store:
        name = STORE_NAMES.get(funct3, f"s?{funct3}")
        return f"{name} x{rs2}, {simm}(x{rs1})"
    if is_branch:
        name = BRANCH_NAMES.get(funct3, f"b?{funct3}")
        return f"{name} x{rs1}, x{rs2}, {simm}"
    if opcode == OPCODE_JAL:
        return f"jal x{rd}, {simm}"
    if opcode == OPCODE_JALR:
        return f"jalr x{rd}, {simm}(x{rs1})"
    if opcode == OPCODE_LUI:
        return f"lui x{rd}, 0x{(imm >> 12) & 0xFFFFF:x}"
    if opcode == OPCODE_AUIPC:
        return f"auipc x{rd}, 0x{(imm >> 12) & 0xFFFFF:x}"
    if opcode in (OPCODE_OP, OPCODE_OP_IMM):
        name = ALU_OP_NAMES.get(alu_op, f"alu?{alu_op:x}")
        if is_immediate:
            if name in ("sll", "srl", "sra"):
                return f"{name}i x{rd}, x{rs1}, {imm & 0x1f}"
            return f"{name}i x{rd}, x{rs1}, {simm}"
        return f"{name} x{rd}, x{rs1}, x{rs2}"

    return f"unknown(op=0x{opcode:02x} f3={funct3})"


class _InFlightInsn:
    __slots__ = ("pc", "instr")

    def __init__(self, pc, instr):
        self.pc = pc
        self.instr = instr


class CpuTracer(uvm_component):
    """
    Passive component that maintains an in-order software queue of
    in-flight instructions (pushed at IF, matched/popped at ALU/LSU
    retirement) and emits a Spike-style trace to CPU_TRACE_FILE
    (default cpu_trace.log in the sim run directory).
    """

    def build_phase(self):
        super().build_phase()
        self.logger = logging.getLogger("my_cpu_tb." + self.get_name())
        self.dut = cocotb.top

        self._queue = deque()
        self._last_if_pc = None
        self._last_if_valid = False

        self._trace_path = os.environ.get("CPU_TRACE_FILE", DEFAULT_TRACE_FILE)
        self._trace_file = None
        if self._trace_path:
            self._trace_file = open(self._trace_path, "w")

    def _val(self, sig, default=None):
        try:
            v = sig.value
        except AttributeError:
            return default
        if hasattr(v, "to_unsigned"):
            try:
                return v.to_unsigned()
            except ValueError:
                return default
        try:
            return int(v)
        except (TypeError, ValueError):
            return default

    def _emit(self, pc, instr, rd, writes_rd, wb_data, is_load, is_store, mem_addr,
               opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2, imm):
        if self._trace_file is None:
            return

        mnemonic = disassemble(opcode, funct3, alu_op, is_immediate, is_branch,
                                is_jump, is_load, is_store, rd, rs1, rs2, imm)

        disasm_line = f"core   0: 0x{pc & 0xFFFFFFFF:08x} (0x{instr & 0xFFFFFFFF:08x}) {mnemonic}"

        commit_line = f"core   0: 3 0x{pc & 0xFFFFFFFF:08x} (0x{instr & 0xFFFFFFFF:08x})"
        if writes_rd and rd != 0:
            commit_line += f" x{rd} 0x{wb_data & 0xFFFFFFFF:08x}"
        if is_load or is_store:
            commit_line += f" mem 0x{mem_addr & 0xFFFFFFFF:08x}"

        self._trace_file.write(disasm_line + "\n")
        self._trace_file.write(commit_line + "\n")

    async def run_phase(self):
        if self.dut is None:
            self.dut = cocotb.top

        while True:
            await RisingEdge(self.dut.clk)

            # ── 1. Push newly-arrived instructions from IF into the queue ──
            if_id_valid = bool(self._val(getattr(self.dut, "if_id_valid", None), 0))
            if_id_pc = self._val(getattr(self.dut, "if_id_pc", None), 0)
            if_id_instr = self._val(getattr(self.dut, "if_id_instr", None), 0)

            is_new_entry = if_id_valid and (
                not self._last_if_valid or if_id_pc != self._last_if_pc
            )
            if is_new_entry:
                self._queue.append(_InFlightInsn(if_id_pc, if_id_instr))

            self._last_if_valid = if_id_valid
            self._last_if_pc = if_id_pc

            # ── 2. Match ALU/LSU retirement events against the queue ──
            alu_valid = bool(self._val(getattr(self.dut, "alu_retire_valid", None), 0))
            lsu_valid = bool(self._val(getattr(self.dut, "lsu_valid", None), 0))
            # BRANCH-opcode uops (is_branch) are resolved entirely inside
            # ISSUE (rtl/pipeline/issue.sv: alu_if.m_valid/lsu_if.m_valid
            # are forced low for is_branch) -- they never reach ALU/LSU, so
            # they must be captured here via the branch-resolution pulse
            # (o_update_valid == issue_en && buf_uop_q.is_branch, wired to
            # bpu_update_valid at tb_top) or they'd never retire in-trace.
            branch_valid = bool(self._val(getattr(self.dut, "bpu_update_valid", None), 0))

            if alu_valid:
                self._retire_from_alu()
            if lsu_valid:
                self._retire_from_lsu()
            if branch_valid:
                self._retire_from_branch()

    def _pop_matching(self, pc):
        """Pop the front of the queue up to and including the first entry
        whose pc matches; entries popped before the match are stale
        (flushed) and are silently dropped. Returns None if no match."""
        dropped = 0
        while self._queue:
            entry = self._queue.popleft()
            if entry.pc == pc:
                if dropped:
                    self.logger.debug(
                        f"cpu_tracer: dropped {dropped} stale/flushed in-flight entr"
                        f"{'y' if dropped == 1 else 'ies'} before matching pc=0x{pc:08x}"
                    )
                return entry
            dropped += 1
        self.logger.warning(
            f"cpu_tracer: no in-flight entry found for retiring pc=0x{pc:08x}; "
            f"trace line for this instruction will be skipped"
        )
        return None

    def _retire_from_alu(self):
        alu = self.dut.ALU
        pc = self._val(getattr(alu, "pc_q", None), 0)
        entry = self._pop_matching(pc)
        if entry is None:
            return

        rd = self._val(getattr(self.dut, "fwd_alu_issue_rd", None), 0)
        writes_rd = bool(self._val(getattr(self.dut, "fwd_alu_issue_writes_rd", None), 0))
        result = self._val(getattr(self.dut, "alu_retire_result", None), 0)

        uop = getattr(alu, "uop_q", None)
        opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2 = \
            self._decode_uop_fields(uop)

        self._emit(entry.pc, entry.instr, rd, writes_rd, result,
                   False, False, 0,
                   opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2,
                   self._extract_imm(uop))

    def _retire_from_lsu(self):
        lsu = self.dut.LSU
        pc = self._val(getattr(lsu, "pc_q", None), 0)
        entry = self._pop_matching(pc)
        if entry is None:
            return

        uop = getattr(lsu, "uop_q", None)
        opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2 = \
            self._decode_uop_fields(uop)
        rd = self._val(getattr(uop, "rd", None), 0) if uop is not None else 0
        writes_rd = bool(self._val(getattr(uop, "writes_rd", None), 0)) if uop is not None else False

        is_load = bool((int(self._val(uop, 0) or 0) >> 37) & 0x1) if uop is not None else False
        is_store = bool((int(self._val(uop, 0) or 0) >> 36) & 0x1) if uop is not None else False

        load_data = self._val(getattr(self.dut, "lsu_load_data", None), 0)
        mem_addr = self._val(getattr(lsu, "mem_addr", None), 0)

        self._emit(entry.pc, entry.instr, rd, writes_rd, load_data,
                   is_load, is_store, mem_addr,
                   opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2,
                   self._extract_imm(uop))

    def _retire_from_branch(self):
        issue = self.dut.ISSUE
        pc = self._val(getattr(self.dut, "bpu_update_pc", None), 0)
        entry = self._pop_matching(pc)
        if entry is None:
            return

        uop = getattr(issue, "buf_uop_q", None)
        opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2 = \
            self._decode_uop_fields(uop)

        self._emit(entry.pc, entry.instr, 0, False, 0,
                   False, False, 0,
                   opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2,
                   self._extract_imm(uop))

    def _decode_uop_fields(self, uop):
        """Pull opcode/funct3/alu_op/is_immediate/is_branch/is_jump/rs1/rs2
        straight off the packed uop_t handle via sub-field access, falling
        back to manual bit-slicing of the raw packed value if needed."""
        if uop is None:
            return 0, 0, 0, False, False, False, 0, 0

        def fld(name, bits=None, default=0):
            try:
                sub = getattr(uop, name)
                v = self._val(sub, None)
                if v is not None:
                    return v
            except AttributeError:
                pass
            if bits is not None:
                raw = self._val(uop, 0) or 0
                msb, lsb = bits
                return (raw >> lsb) & ((1 << (msb - lsb + 1)) - 1)
            return default

        opcode = fld("opcode", (110, 104))
        funct3 = fld("funct3", (78, 76))
        alu_op = fld("alu_op", (103, 94))
        is_immediate = bool(fld("is_immediate", (40, 40)))
        is_branch = bool(fld("is_branch", (39, 39)))
        is_jump = bool(fld("is_jump", (38, 38)))
        rs1 = fld("rs1", (93, 89))
        rs2 = fld("rs2", (88, 84))

        return opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2

    def _extract_imm(self, uop):
        if uop is None:
            return 0
        try:
            v = self._val(getattr(uop, "imm", None), None)
            if v is not None:
                return v
        except AttributeError:
            pass
        raw = self._val(uop, 0) or 0
        return (raw >> 44) & 0xFFFFFFFF

    def final_phase(self):
        super().final_phase()
        if self._trace_file is not None:
            self._trace_file.flush()
            self._trace_file.close()
            self._trace_file = None
