# Simulator
SIM ?= verilator

# Top-level module
TOPLEVEL = tb_top

# cocotb Python entry
MODULE = run_test

# Verilog/SystemVerilog sources
VERILOG_SOURCES = 				\
  ../../rtl/include/*.sv 		\
  ../../rtl/interfaces/*.sv 	\
  ../../rtl/pipeline/*.sv 		\
  ../../rtl/tb_top.sv

# Enable SystemVerilog
VERILATOR_ARGS += --sv --trace --trace-structs

# Clock name
TOPLEVEL_LANG = verilog

# Python path for pyUVM
export PYTHONPATH := $(PWD)/../../test_bench

# Generate Waveform
export VERILATOR_TRACE = 1
export VERILATOR_TRACE_DEPTH = 99

# Include cocotb makefiles
include $(shell cocotb-config --makefiles)/Makefile.sim
