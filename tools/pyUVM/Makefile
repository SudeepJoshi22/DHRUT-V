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
# --assert +define+SIMULATION: the RTL's SVA checks (ifetch.sv,
# fetch_queue.sv, bpu.sv) are wrapped in `ifdef SIMULATION`, and nothing
# used to define it - so every one of them was dead code in the normal
# flow. That mattered: fetch_queue's assert_no_overflow would have caught
# the queue-overflow bug (an instruction silently dropped) the moment it
# happened. Both flags are needed - the define compiles the assertions
# in, --assert makes Verilator actually evaluate them.
# VCD tracing is the dominant cost on long runs -- CoreMark is millions of
# cycles and the dump grows into the gigabytes -- so it is optional. Waves are
# on by default because they are what you want while debugging; turn them off
# for benchmarking:
#     WAVES=0 ./tools/simulate_c.sh coremark tests/bench/coremark/*.c
# The instruction trace (cpu_trace.log) is written either way, so Spike
# comparison and IPC still work with WAVES=0.
WAVES ?= 1

EXTRA_ARGS += --sv -Wno-MULTIDRIVEN --assert +define+SIMULATION
ifeq ($(WAVES),1)
EXTRA_ARGS += --trace --trace-structs
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
