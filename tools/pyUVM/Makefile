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
  $(REPO_ROOT)/rtl/interfaces/*.sv \
  $(REPO_ROOT)/rtl/pipeline/*.sv \
  $(REPO_ROOT)/rtl/tb_top.sv

# pyUVM python path (absolute)
export PYTHONPATH := $(REPO_ROOT)/test_bench:$(PYTHONPATH)

# Verilator args
EXTRA_ARGS += --sv --trace --trace-structs

include $(shell cocotb-config --makefiles)/Makefile.sim
