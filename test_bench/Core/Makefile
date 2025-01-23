SIM ?= icarus
TOPLEVEL_LANG ?= verilog
RTL_DIR ?= $(PWD)/../../rtl/

VERILOG_SOURCES += $(RTL_DIR)/parameters.vh
VERILOG_SOURCES += $(RTL_DIR)/top_module.v
VERILOG_SOURCES += $(RTL_DIR)/Core.v
VERILOG_SOURCES += $(RTL_DIR)/Fetch.v
VERILOG_SOURCES += $(RTL_DIR)/bpu.v
VERILOG_SOURCES += $(RTL_DIR)/Decode.v
VERILOG_SOURCES += $(RTL_DIR)/reg_file.v
VERILOG_SOURCES += $(RTL_DIR)/imm_gen.v
VERILOG_SOURCES += $(RTL_DIR)/control_unit.v
VERILOG_SOURCES += $(RTL_DIR)/Execute.v
VERILOG_SOURCES += $(RTL_DIR)/alu.v
VERILOG_SOURCES += $(RTL_DIR)/Memory.v
VERILOG_SOURCES += $(RTL_DIR)/Writeback.v
VERILOG_SOURCES += $(RTL_DIR)/instr_mem.v
VERILOG_SOURCES += $(RTL_DIR)/data_ram.v



fetch:
	rm -rf sim_build/
	$(MAKE) sim MODULE=test_core TOPLEVEL=top_module
include $(shell cocotb-config --makefiles)/Makefile.sim
