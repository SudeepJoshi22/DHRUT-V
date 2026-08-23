SIM ?= verilator
TOPLEVEL = tb_top
MODULE = run_test
TOPLEVEL_LANG = verilog

# Directory where THIS Makefile lives (works even when called via `make -f ...`)
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Repo root (pyUVM is tools/pyUVM, so repo root is two levels up)
REPO_ROOT := $(abspath $(MAKEFILE_DIR)/../..)

# Verilog/SystemVerilog sources (absolute paths, globs ok)
VERILOG_SOURCES = \
  $(REPO_ROOT)/rtl/include/*.sv \
  $(REPO_ROOT)/rtl/csr/generated/csr_regfile_gen_pkg.sv \
  $(REPO_ROOT)/rtl/csr/generated/csr_regfile_gen.sv \
  $(REPO_ROOT)/rtl/interfaces/*.sv \
  $(REPO_ROOT)/rtl/pipeline/*.sv \
  $(REPO_ROOT)/rtl/cpu_core.sv \
  $(REPO_ROOT)/rtl/tb_top.sv

# pyUVM python path (absolute)
export PYTHONPATH := $(REPO_ROOT)/test_bench:$(PYTHONPATH)

# Verilator args
# -Wno-MULTIDRIVEN: PeakRDL-regblock generates one always_comb/always_ff pair
# per field, each writing only its own disjoint member of the shared
# field_combo/field_storage packed struct (rtl/csr/generated/) - legal SV,
# but Verilator flags it at whole-variable granularity. Known false positive.
EXTRA_ARGS += --sv --trace --trace-structs -Wno-MULTIDRIVEN

include $(shell cocotb-config --makefiles)/Makefile.sim
