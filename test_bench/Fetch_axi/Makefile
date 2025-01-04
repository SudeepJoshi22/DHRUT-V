SIM ?= icarus
TOPLEVEL_LANG ?= verilog
RTL_DIR ?= $(PWD)/../../rtl/

VERILOG_SOURCES += $(RTL_DIR)/parameters.vh
VERILOG_SOURCES += $(PWD)/tb_fetch_imem_interface.v
VERILOG_SOURCES += $(RTL_DIR)/Fetch.v
VERILOG_SOURCES += $(RTL_DIR)/bpu.v
VERILOG_SOURCES += $(RTL_DIR)/instr_mem.v

mem:
	rm -rf sim_build/
	$(MAKE) sim MODULE=test_fetch_imem_interface TOPLEVEL=tb_fetch_imem_interface
include $(shell cocotb-config --makefiles)/Makefile.sim
