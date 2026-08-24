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

clean:
	rm -f $(JSON) $(PACK_JSON) $(BITSTREAM)

.PHONY: check synth bitstream flash flash-nv clean