# File list for cpu_core synthesis (Yosys -f format: one file per line,
# '#' for comments). Order matters — packages and interfaces must appear
# before anything that imports/instantiates them.

../rtl/include/riscv_uop_pkg.sv
../rtl/csr/generated/csr_regfile_gen_pkg.sv
../rtl/interfaces/mem_if.sv
../rtl/interfaces/issue_interfaces.sv
../rtl/csr/generated/csr_regfile_gen.sv
../rtl/pipeline/ARF.sv
../rtl/pipeline/alu.sv
../rtl/pipeline/alu_stage.sv
../rtl/pipeline/bpu.sv
../rtl/pipeline/csr_unit.sv
../rtl/pipeline/decode.sv
../rtl/pipeline/ifetch.sv
../rtl/pipeline/issue.sv
../rtl/pipeline/lsu.sv
../rtl/pipeline/retire.sv
../rtl/cpu_core.sv