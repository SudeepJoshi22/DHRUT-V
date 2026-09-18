# Equivalence proofs for the area-optimisation rewrites

Area work on `rtl/pipeline/` rewrote two datapaths to share arithmetic that the
original code instantiated once per `case` arm. Both rewrites are supposed to be
*exactly* equivalent to what they replaced, and "the regression still passes" is
not evidence of that -- the tests exercise a handful of operand values, while the
claim is about every input.

These are SymbiYosys/Z3 proofs of the claim. Both are combinational, so BMC at
depth 1 is a complete proof, not a bounded one: there is no state to unroll.

## Running them

```bash
source tools/oss-cad-suite/environment
cd fpga/formal
sby -f alu_equiv.sby --yosys "yosys -m slang"
sby -f lsu_equiv.sby --yosys "yosys -m slang"
```

`--yosys "yosys -m slang"` is required. Yosys' built-in Verilog frontend cannot
parse the `alu_op_t` enum port on `alu`, and fails with a syntax error on the
port list; the slang frontend used by the rest of the FPGA flow handles it.

## What each proves

**alu_equiv** -- the shared-datapath `alu.sv` against the original
one-operator-per-arm version, over every `(op1, op2, alu_op)`: 2^69 input
combinations. The original built three 32-bit shifters and three subtractors;
the rewrite shares one adder and one shifter, deriving SLT/SLTU from the shared
subtract's borrow.

**lsu_equiv** -- the store align/strobe and load align/extend datapaths of
`lsu.sv`, over every `(data, offset, size, sign_extend, is_store)`. Store data is
compared only on lanes the strobe enables, since a disabled lane's contents are
don't-care and the two versions may legitimately differ there. Note the
misaligned-halfword cases (offset 1 and 3): the original mapped them to a zero
strobe and a zero load result via `default`, and the rewrite reproduces that
explicitly through `h_aligned` rather than relying on the shift to do it.

**mdu_equiv** -- the RV32M unit (`rtl/pipeline/mdu.sv`) against a reference
built from SystemVerilog's own `*`, `/` and `%`. All eight operations, and
the three things the spec calls out that implementations get wrong: divide
by zero (no trap), signed overflow `-2^(XLEN-1) / -1` (no trap), and
MULHSU's signed-times-unsigned asymmetry.

Run at **XLEN=8**, not 32, and that limit is deliberate -- see the header of
`mdu_equiv.sv`. Both algorithms are uniform in width, so the narrow proof
covers the structure and every special case; the real 32-bit width is
covered by `tests/asm/mul_div.S` and the riscof M suite.

Two things this proof caught that review had not: BMC starts from an
arbitrary state rather than a reset one (the harness now pins the first
cycle to reset), and the REFERENCE was wrong before the DUT was -- an
unsigned ternary arm silently made `$signed(a)/$signed(b)` an unsigned
divide.

A proof that passes prints `DONE (PASS, rc=0)`. A failure writes a counterexample
trace naming the exact inputs that diverge.
