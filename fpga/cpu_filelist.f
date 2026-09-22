# CPU sources in dependency order: packages/interfaces precede their users.

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
# decoder.sv: one stateless decode lane, instantiated by decode.sv
../rtl/pipeline/decoder.sv
../rtl/pipeline/fetch_queue.sv
# forward_unit.sv: operand bypass network, instantiated by issue.sv
../rtl/pipeline/forward_unit.sv
../rtl/pipeline/ifetch.sv
../rtl/pipeline/issue.sv
# issue_hazard.sv: dual-issue pairing rules, instantiated by issue.sv
../rtl/pipeline/issue_hazard.sv
../rtl/pipeline/lsu.sv
# mdu.sv: RV32M multiply/divide, instantiated by cpu_core.sv
../rtl/pipeline/mdu.sv
# ras.sv: return address stack, instantiated by ifetch.sv
../rtl/pipeline/ras.sv
../rtl/pipeline/retire.sv
# scoreboard.sv: outstanding-write counters, instantiated by issue.sv
../rtl/pipeline/scoreboard.sv
../rtl/cpu_core.sv
