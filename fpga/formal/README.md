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

A proof that passes prints `DONE (PASS, rc=0)`. A failure writes a counterexample
trace naming the exact inputs that diverge.
