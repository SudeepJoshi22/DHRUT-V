SIM ?= icarus
TOPLEVEL_LANG ?= verilog
RTL_DIR ?= $(PWD)/../../rtl/

VERILOG_SOURCES += $(RTL_DIR)/parameters.vh
VERILOG_SOURCES += $(PWD)/tb_fetch_axil_interface.v
VERILOG_SOURCES += $(RTL_DIR)/Fetch.v
VERILOG_SOURCES += $(RTL_DIR)/axil_rom.v
VERILOG_SOURCES += $(RTL_DIR)/bpu.v

fetch:
	rm -rf sim_build/
	$(MAKE) sim MODULE=test_fetch_axil_interface TOPLEVEL=tb_fetch_axil_interface
include $(shell cocotb-config --makefiles)/Makefile.sim
