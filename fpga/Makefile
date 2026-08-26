# Open-source build flow for the Sipeed Tang Nano 20K (GW2AR-18 / GW2AR-LV18QN88C8/I7)
# Requires OSS CAD Suite tools on your PATH: yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader
#
# ---- Quick resource/synthesis check (no PnR, no .cst needed) --------------
#   make check TOP=<top_module> FILELIST=<file.f>
#     e.g. make check TOP=cpu_core FILELIST=cpu_core.f
#          make check TOP=blink    FILELIST=blink.f
#   -> elaborates + maps to Gowin primitives + prints `stat` (LUT/FF/BRAM/DSP).
#      Use this for anything that doesn't have physical top-level ports yet.
#
#   make synth TOP=<top_module> FILELIST=<file.f>
#     Same as `check`, but also writes <top_module>.json (the netlist),
#     in case you want to inspect it or feed it to PnR later.
#
# A <name>.f file lists RTL source files one per line (Yosys `-f` filelist
# format; '#' comments allowed). Order matters: packages/interfaces must
# come before files that import/instantiate them.
#
# ---- Full board flow: synth + PnR + pack + flash ---------------------------
#   make bitstream TOP=<top_module> FILELIST=<file.f> CST=<pins.cst>
#     e.g. make bitstream TOP=blink FILELIST=blink.f CST=tangnano20k.cst
#   make flash    TOP=... FILELIST=... CST=...   -> flash to SRAM (temporary)
#   make flash-nv TOP=... FILELIST=... CST=...   -> flash to onboard flash
#
#   make clean TOP=<top_module>   -> remove that top's generated files
#
# ---- CPU on hardware -------------------------------------------------------
# cpu_core has SystemVerilog *interface* ports (mem_if.master imem_if/dmem_if),
# so it cannot be a synthesis top on its own -- there is no parent to
# instantiate the interfaces, and a .cst can only constrain flat scalar ports.
# rtl/cpu_top.sv is the wrapper: it instantiates the two mem_if instances at
# the right widths (imem 64-bit, dmem 32-bit), hooks cpu_core onto them, backs
# both with BSRAM, and exposes clk/rst_n_btn/led.
#
#   make mem TEST=add                                   # program image -> *.hex
#   make check     TOP=cpu_top FILELIST=cpu_top_filelist.f
#   make bitstream TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst
#   make flash     TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst
#
# Run `make mem` FIRST: cpu_top's $readmemh reads imem_init.hex/dmem_init.hex
# from this directory at elaboration time, so synthesis needs them present.

DEVICE     = GW2AR-LV18QN88C8/I7
FAMILY     = GW2A-18C

# Defaults — override any of these on the command line, e.g.:
#   make check TOP=cpu_core FILELIST=cpu_core.f
TOP        ?= blink
FILELIST   ?= blink.f
CST        ?= tangnano20k.cst

JSON       = $(TOP).json
PACK_JSON  = $(TOP).pack.json
BITSTREAM  = $(TOP).fs

# ---- Synthesis-only: resource check, no PnR, no CST required ---------------
# Turns a .f filelist into a space-separated file list, fed to `read_slang`
# in ONE call (the slang-based frontend, via the sv-elab plugin bundled in
# OSS CAD Suite). Unlike Yosys's built-in -sv frontend, read_slang is a
# full SystemVerilog elaborator — it handles unpacked structs/arrays,
# interfaces, etc. correctly, so generated code (e.g. PeakRDL output)
# doesn't need to be patched to work here.
BUILD_FILES = FILES=$$(grep -v '^[[:space:]]*\#' $(FILELIST) | grep -v '^[[:space:]]*$$' | tr '\n' ' ');

check:
	$(BUILD_FILES) yosys -m slang -p "read_slang $$FILES --top $(TOP); synth_gowin -top $(TOP); stat"

synth:
	$(BUILD_FILES) yosys -m slang -p "read_slang $$FILES --top $(TOP); synth_gowin -top $(TOP) -json $(JSON); stat"

# ---- Full flow: synth -> PnR -> pack -> (optionally) flash -----------------
$(JSON): $(FILELIST)
	$(BUILD_FILES) yosys -m slang -p "read_slang $$FILES --top $(TOP); synth_gowin -top $(TOP) -json $(JSON)"

$(PACK_JSON): $(JSON) $(CST)
	nextpnr-himbaechel \
		--json $(JSON) \
		--write $(PACK_JSON) \
		--device $(DEVICE) \
		--vopt family=$(FAMILY) \
		--vopt cst=$(CST)

$(BITSTREAM): $(PACK_JSON)
	gowin_pack -d $(FAMILY) -o $(BITSTREAM) $(PACK_JSON)

bitstream: $(BITSTREAM)

flash: $(BITSTREAM)
	openFPGALoader -b tangnano20k $(BITSTREAM)

flash-nv: $(BITSTREAM)
	openFPGALoader -b tangnano20k -f $(BITSTREAM)

# ---- Program image for cpu_top's BSRAMs ------------------------------------
# Converts a test built by tools/simulate.sh into the two $readmemh files
# cpu_top instantiates its BSRAMs with. mkmem.py also prints the program's real
# .tohost address, which tests/linker.ld floats after .text -- pass it through
# as TOHOST_ADDR if it differs from cpu_top.sv's default, or the PASS LED will
# never light.
TEST ?= add
TEST_DIR = ../tests/build/$(TEST)

mem:
	./mkmem.py $(TEST_DIR)/$(TEST).hex --elf $(TEST_DIR)/$(TEST).elf --outdir .

clean:
	rm -f $(JSON) $(PACK_JSON) $(BITSTREAM)

clean-mem:
	rm -f imem_init.hex dmem_init.hex

.PHONY: check synth bitstream flash flash-nv clean clean-mem mem