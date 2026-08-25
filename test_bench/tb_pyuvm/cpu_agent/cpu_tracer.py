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
does not carry the PC past decode, so the PC (and the raw instruction
word alongside it) has to be captured earlier and carried forward in
software, keyed to the instruction that eventually completes execution in
ALU/LSU.

Where it is captured: at the Decode -> Issue hand-off, driven by
`issue_accept_cnt` (rtl/cpu_core.sv) -- the exact number of decode slots
Issue consumed this cycle. That count is the handshake the RTL itself
uses, so it cannot disagree with what actually entered the pipeline. It
replaces an older heuristic ("IF valid and the PC changed"), which a
2-wide decode breaks in two ways: more than one instruction can leave the
queue in a single cycle, and a self-targeting jump (`j .`) re-presents the
same PC without it being the same dynamic instruction.

The pipeline is in-order, and (per rtl/cpu_core.sv) only IF/decode/issue
are squashed on `mispredict` -- ALU0/ALU1/LSU/RETIRE0/RETIRE1 all run
i_flush=1'b0, so once dispatched an instruction always completes. That
invariant is upheld by Issue refusing to dispatch lane 1 alongside a
redirecting lane 0 (issue.sv: `issue_en1` is gated on `!o_mispredict`),
so no wrong-path uop ever enters an ALU. It means "retirement" can be
detected directly off the units' o_valid without waiting an extra cycle
for the retire_wb_* registers, and the associated PC/uop read straight
from ALUn.pc_q/uop_q or LSU.pc_q/uop_q.

Two issue lanes, so up to TWO instructions retire per cycle. They are
emitted in program order within the cycle: lane 0's completion (ALU0 or
LSU -- mutually exclusive, asserted in cpu_core.sv) before lane 1's
(ALU1). Order matters more than it looks: _pop_matching consumes the
queue by PC and silently drops anything in front of the match, so
emitting a younger instruction first would discard the older one as
"flushed" and corrupt the queue for the rest of the run.

Note the branch case is a stage EARLIER than the others -- it is caught
at Issue via the BPU-update pulse, not at completion -- so a branch seen
in cycle N belongs to a YOUNGER bundle than an ALU/LSU completion seen in
the same cycle. It is therefore emitted last.

Hierarchy: these pipeline signals live inside the cpu_core instance
(tb_top.CORE.*), reached via hier.get_core() rather than a hardcoded path
so further hierarchy changes (e.g. superscalar rework) don't silently
break tracing again.

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

from . import hier

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

# Total width of uop_t, needed to slice a slot out of the packed 2-wide
# decode bundle (idg_uop). Keep in sync with riscv_uop_pkg.sv.
UOP_W = 146

# Bit positions of uop_t fields within the packed 146-bit struct, used as a
# fallback when per-field handles aren't exposed by the simulator.
# Derived from rtl/include/riscv_uop_pkg.sv - in a packed struct the FIRST
# declared field occupies the MSBs. `way` was added at the very top
# precisely so it takes bit 145 and leaves every offset below it alone:
#   way 145 | valid 144 | opcode 143:137 | alu_op 136:127 | rs1 126:122 | rs2 121:117
#   rd 116:112 | funct3 111:109 | imm 108:77 | uses_rs1 76 | uses_rs2 75
#   writes_rd 74 | is_immediate 73 | is_branch 72 | is_jump 71 | is_load 70
#   is_store 69 | lsu_sign_extend 68 | lsu_access_size 67:66 | pred_taken 65
#   pred_target 64:33 | is_illegal 32 | instr_bits 31:0
# Keep in sync with riscv_uop_pkg.sv if the struct changes.
UOP_BITS = {
    "valid":        (144, 144),
    "opcode":       (143, 137),
    "alu_op":       (136, 127),
    "rs1":          (126, 122),
    "rs2":          (121, 117),
    "rd":           (116, 112),
    "funct3":       (111, 109),
    "imm":          (108, 77),
    "uses_rs1":     (76, 76),
    "uses_rs2":     (75, 75),
    "writes_rd":    (74, 74),
    "is_immediate": (73, 73),
    "is_branch":    (72, 72),
    "is_jump":      (71, 71),
    "is_load":      (70, 70),
    "is_store":     (69, 69),
    "lsu_access_size": (67, 66),
    "pred_taken":   (65, 65),
    "is_illegal":   (32, 32),
    "instr_bits":   (31, 0),
}


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
        # Pipeline signals live inside the cpu_core instance (tb_top.CORE.*);
        # resolved via hier so this survives further hierarchy changes.
        self.core = hier.get_core(self.dut)

        self._queue = deque()

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
               opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2, imm,
               store_data=None, store_size=2):
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
            # Spike's --log-commits prints the stored value after the address
            # for stores (loads instead report the loaded value as the rd write).
            # It prints only the bytes the access actually writes -- 0x2a for
            # an SB, 0x0054 for an SH -- so mask and width-format to match,
            # or every sub-word store shows as a spurious trace diff.
            if is_store and store_data is not None:
                nibbles = {0: 2, 1: 4}.get(store_size, 8)
                mask = (1 << (nibbles * 4)) - 1
                commit_line += f" 0x{store_data & mask:0{nibbles}x}"

        self._trace_file.write(disasm_line + "\n")
        self._trace_file.write(commit_line + "\n")

    async def run_phase(self):
        if self.dut is None:
            self.dut = cocotb.top
        if self.core is None:
            self.core = hier.get_core(self.dut)

        while True:
            await RisingEdge(self.dut.clk)

            # ── 1. Push the uops Issue accepted from Decode this cycle ──
            # idg_pc / idg_uop are packed 2-wide bundles (slot 0 in the low
            # bits, slot 0 = the older instruction). accept_cnt says how many
            # of them, starting at slot 0, actually entered Issue.
            accept_cnt = self._val(getattr(self.core, "issue_accept_cnt", None), 0)
            if accept_cnt:
                pc_bus = self._val(getattr(self.core, "idg_pc", None), 0)
                uop_bus = self._val(getattr(self.core, "idg_uop", None), 0)
                for slot in range(min(accept_cnt, 2)):
                    pc = (pc_bus >> (32 * slot)) & 0xFFFFFFFF
                    # instr_bits is uop_t[31:0], so it falls at the bottom of
                    # each slot's slice.
                    instr = (uop_bus >> (UOP_W * slot)) & 0xFFFFFFFF
                    self._queue.append(_InFlightInsn(pc, instr))

            # ── 2. Match retirement events against the queue ──
            alu0_valid = bool(self._val(getattr(self.core, "alu0_retire_valid", None), 0))
            alu1_valid = bool(self._val(getattr(self.core, "alu1_retire_valid", None), 0))
            lsu_valid = bool(self._val(getattr(self.core, "lsu_valid", None), 0))
            # BRANCH-opcode uops (is_branch) are resolved entirely inside
            # ISSUE (rtl/pipeline/issue.sv: alu0_if.m_valid/lsu_if.m_valid
            # are forced low for is_branch) -- they never reach ALU/LSU, so
            # they must be captured here via the branch-resolution pulse
            # (o_update_valid == issue_en0 && buf_uop0_q.is_branch, wired to
            # bpu_update_valid at cpu_core) or they'd never retire in-trace.
            branch_valid = bool(self._val(getattr(self.core, "bpu_update_valid", None), 0))

            # Program order within the cycle -- see the module docstring.
            # ALU0 and LSU are mutually exclusive, so their relative order
            # here is arbitrary; ALU1 must follow both, and the branch pulse
            # (a stage earlier, hence a younger bundle) must come last.
            if alu0_valid:
                self._retire_from_alu(0)
            if lsu_valid:
                self._retire_from_lsu()
            if alu1_valid:
                self._retire_from_alu(1)
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

    def _retire_from_alu(self, lane):
        """Emit the instruction completing in ALU lane `lane` (0 or 1).

        The two ALUs are separate module instances (CORE.ALU0 / CORE.ALU1)
        rather than one widened module, precisely so these stay plain
        scalar handles -- Verilator's VPI would present a packed
        `logic [1:0][31:0] pc_q` as one flat 64-bit vector and silently
        hand back a concatenation of both lanes.
        """
        alu = getattr(self.core, f"ALU{lane}", None)
        if alu is None:
            return
        pc = self._val(getattr(alu, "pc_q", None), 0)
        entry = self._pop_matching(pc)
        if entry is None:
            return

        result = self._val(getattr(self.core, f"alu{lane}_retire_result", None), 0)

        uop = getattr(alu, "uop_q", None)
        opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2 = \
            self._decode_uop_fields(uop)
        # Taken straight off the retiring uop rather than off the forwarding
        # bus: same values, one fewer per-lane signal name to keep in sync.
        rd = self._uop_field(uop, "rd")
        writes_rd = bool(self._uop_field(uop, "writes_rd"))

        self._emit(entry.pc, entry.instr, rd, writes_rd, result,
                   False, False, 0,
                   opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2,
                   self._extract_imm(uop))

    def _retire_from_lsu(self):
        lsu = self.core.LSU
        pc = self._val(getattr(lsu, "pc_q", None), 0)
        entry = self._pop_matching(pc)
        if entry is None:
            return

        uop = getattr(lsu, "uop_q", None)
        opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2 = \
            self._decode_uop_fields(uop)
        rd = self._uop_field(uop, "rd")
        writes_rd = bool(self._uop_field(uop, "writes_rd"))

        is_load = bool(self._uop_field(uop, "is_load"))
        is_store = bool(self._uop_field(uop, "is_store"))

        load_data = self._val(getattr(self.core, "lsu_load_data", None), 0)
        mem_addr = self._val(getattr(lsu, "mem_addr", None), 0)
        # Raw (pre-alignment) register value being stored, matching the
        # architectural value Spike reports; wdata_aligned is the
        # byte-lane-shifted bus value, which Spike does not print.
        store_data = self._val(getattr(lsu, "store_data_q", None), 0) if is_store else None
        # 00 = byte, 01 = halfword, 10 = word (riscv_uop_pkg.sv)
        store_size = self._uop_field(uop, "lsu_access_size")

        self._emit(entry.pc, entry.instr, rd, writes_rd, load_data,
                   is_load, is_store, mem_addr,
                   opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2,
                   self._extract_imm(uop), store_data=store_data,
                   store_size=store_size)

    def _retire_from_branch(self):
        issue = self.core.ISSUE
        pc = self._val(getattr(self.core, "bpu_update_pc", None), 0)
        entry = self._pop_matching(pc)
        if entry is None:
            return

        uop = getattr(issue, "buf_uop0_q", None)
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

        opcode = self._uop_field(uop, "opcode")
        funct3 = self._uop_field(uop, "funct3")
        alu_op = self._uop_field(uop, "alu_op")
        is_immediate = bool(self._uop_field(uop, "is_immediate"))
        is_branch = bool(self._uop_field(uop, "is_branch"))
        is_jump = bool(self._uop_field(uop, "is_jump"))
        rs1 = self._uop_field(uop, "rs1")
        rs2 = self._uop_field(uop, "rs2")

        return opcode, funct3, alu_op, is_immediate, is_branch, is_jump, rs1, rs2

    def _uop_field(self, uop, name, default=0):
        """Read one uop_t field, preferring a per-field handle and falling
        back to slicing the packed value using UOP_BITS."""
        if uop is None:
            return default
        try:
            v = self._val(getattr(uop, name), None)
            if v is not None:
                return v
        except AttributeError:
            pass
        bits = UOP_BITS.get(name)
        if bits is None:
            return default
        raw = self._val(uop, 0) or 0
        msb, lsb = bits
        return (raw >> lsb) & ((1 << (msb - lsb + 1)) - 1)

    def _extract_imm(self, uop):
        return self._uop_field(uop, "imm")

    def final_phase(self):
        super().final_phase()
        if self._trace_file is not None:
            self._trace_file.flush()
            self._trace_file.close()
            self._trace_file = None
