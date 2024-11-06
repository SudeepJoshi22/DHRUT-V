SIM ?= icarus
TOPLEVEL_LANG ?= verilog
RTL_DIR ?= $(PWD)/../../rtl/

VERILOG_SOURCES += $(PWD)/tb_fetch_rom_wrapper.v
VERILOG_SOURCES += $(RTL_DIR)/parameters.vh
VERILOG_SOURCES += $(RTL_DIR)/bpu.v
VERILOG_SOURCES += $(RTL_DIR)/Fetch.v
VERILOG_SOURCES += $(RTL_DIR)/instr_rom.v


fetch:
	rm -rf sim_build/
	$(MAKE) sim MODULE=test_fetch_rom TOPLEVEL=tb_fetch_rom_wrapper
include $(shell cocotb-config --makefiles)/Makefile.sim
