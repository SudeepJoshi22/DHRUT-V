# File list for cpu_top synthesis (Yosys -f format: one file per line,
# '#' for comments). Order matters — packages and interfaces must appear
# before anything that imports/instantiates them.
#
# This is the FPGA top: cpu_top wraps cpu_core, whose interface ports
# (mem_if.master imem_if/dmem_if) cannot be a synthesis top by themselves.
# Use cpu_filelist.f only for elaborating cpu_core in isolation.

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
../rtl/pipeline/fetch_queue.sv
../rtl/pipeline/ifetch.sv
../rtl/pipeline/issue.sv
../rtl/pipeline/lsu.sv
../rtl/pipeline/retire.sv
../rtl/cpu_core.sv
rtl/bram_slave.sv
rtl/cpu_top.sv
