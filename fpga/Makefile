# Open-source build flow for the Sipeed Tang Nano 20K (GW2AR-18 / GW2AR-LV18QN88C8/I7)
# Requires OSS CAD Suite tools on your PATH: yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader
#
# ---- Quick resource/synthesis check (no PnR, no .cst needed) --------------
#   make check TOP=<top_module> FILELIST=<file.f>
#     e.g. make check TOP=blink   FILELIST=blink.f
#          make check TOP=cpu_top FILELIST=cpu_top_filelist.f
#     NOT cpu_core: it has interface ports and cannot be a top (see below).
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
# Hardware benchmarks use the same Makefile entry point:
#   make benchmark BENCH=dhrystone ITERATIONS=50000
#   make benchmark-upload BENCH=dhrystone ITERATIONS=50000 PORT=/dev/serial/by-id/...
#   make benchmark-flash BENCH=coremark ITERATIONS=1000
#
# Run `make mem` FIRST: cpu_top's $readmemh reads imem_init.hex/dmem_init.hex
# from this directory at elaboration time, so synthesis needs them present.

DEVICE     = GW2AR-LV18QN88C8/I7
FAMILY     = GW2A-18C

# The Tang Nano 20K's oscillator. WITHOUT this nextpnr assumes 12 MHz, reports
# "PASS at 12.00 MHz", and never checks the design against the clock it will
# actually run at -- the Fmax it prints is then an informational by-product
# rather than a met constraint. Set it so timing is genuinely verified, and so
# the placer optimises for the real target.
FREQ_MHZ   = 27
PNR_OPTS   ?=

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

# -nowidelut: map to plain LUT4s instead of the MUX2_LUT5..8 wide-LUT tree.
# Counter-intuitively this is smaller AND easier to route on this design:
#   default     LUT4 17015  MUX2_LUT 5706
#   -nowidelut  LUT4 14257  MUX2_LUT    0
# Wide LUTs also tie groups of LUT4s into clusters that must be placed
# adjacently, and at 87% utilisation that congestion stopped nextpnr's router
# converging (overused wires climbed 18 -> 426 over 136k iterations). Removing
# them drops utilisation to ~69% and frees the placer.
# Override with SYNTH_OPTS= to compare.
SYNTH_OPTS ?= -nowidelut

check:
	$(BUILD_FILES) yosys -m slang -p "read_slang $$FILES --top $(TOP); synth_gowin -top $(TOP) $(SYNTH_OPTS); stat"

synth:
	$(BUILD_FILES) yosys -m slang -p "read_slang $$FILES --top $(TOP); synth_gowin -top $(TOP) $(SYNTH_OPTS) -json $(JSON); stat"

# ---- Full flow: synth -> PnR -> pack -> (optionally) flash -----------------
# The netlist depends on every source the filelist NAMES, not just on the
# filelist itself. Depending on $(FILELIST) alone meant that editing RTL
# without touching the list left a stale .json in place: make skipped
# synthesis and nextpnr ran on the old netlist. That surfaced as a baffling
# "ERROR: Unconstrained IO:rst_n_btn_IBUF_I" after a port was renamed -- the
# netlist still had the old port name while the .cst had the new one.
SRCS = $(shell grep -v '^[[:space:]]*\#' $(FILELIST) 2>/dev/null | grep -v '^[[:space:]]*$$')

# Program contents are baked into the netlist; changing make mem must rebuild it.
ifeq ($(TOP),cpu_top)
MEMORY_IMAGES = $(foreach b,0 1 2 3 4 5 6 7,imem_init_b$(b).hex) imem_init.hex dmem_init_b0.hex dmem_init_b1.hex dmem_init_b2.hex dmem_init_b3.hex
endif

$(JSON): $(FILELIST) $(SRCS) $(MEMORY_IMAGES)
	$(BUILD_FILES) yosys -m slang -p "read_slang $$FILES --top $(TOP); synth_gowin -top $(TOP) $(SYNTH_OPTS) -json $(JSON)"

$(PACK_JSON): $(JSON) $(CST)
	nextpnr-himbaechel \
		--json $(JSON) \
		--write $(PACK_JSON) \
		--device $(DEVICE) \
		--freq $(FREQ_MHZ) \
		$(PNR_OPTS) \
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

# ---- Hardware benchmark build, bake, flash and UART run -------------------
# Python implements ELF construction and the serial protocol, while make is
# the operator-facing workflow and owns composition with synthesis/flash.
PYTHON          ?= python3
BENCH           ?= dhrystone
ITERATIONS      ?= 1
VALIDATION      ?= 0
CLOCK_HZ        ?= 27000000
PORT            ?=
TIMEOUT         ?= 120
EXPECTED_ERRORS ?= 0
BRAM_TEST       ?= dhrystone_edgefix
EXPECTED_CYCLES ?=

VALIDATION_ENABLED = $(filter 1 yes true,$(VALIDATION))
VALIDATION_ARG     = $(if $(VALIDATION_ENABLED),--validation,)
BENCH_SUFFIX       = $(if $(VALIDATION_ENABLED),_validation,)
BENCH_TEST         = $(BENCH)_hw_$(ITERATIONS)$(BENCH_SUFFIX)
BENCH_DIR          = ../tests/build/$(BENCH_TEST)
BENCH_ELF          = $(BENCH_DIR)/$(BENCH_TEST).elf
BENCH_HEX          = $(BENCH_DIR)/$(BENCH_TEST).hex
LOG                ?= $(BENCH_TEST).log

benchmark:
	$(PYTHON) ./build_benchmark.py $(BENCH) --iterations $(ITERATIONS) \
		--clock-hz $(CLOCK_HZ) $(VALIDATION_ARG)

benchmark-mem: benchmark
	./mkmem.py $(BENCH_HEX) --elf $(BENCH_ELF) --outdir .

benchmark-bitstream: benchmark-mem
	$(MAKE) bitstream TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst

benchmark-flash: benchmark-mem
	$(MAKE) flash TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst

benchmark-flash-nv: benchmark-mem
	$(MAKE) flash-nv TOP=cpu_top FILELIST=cpu_top_filelist.f CST=cpu_top.cst

benchmark-upload:
	@test -n "$(PORT)" || { echo "PORT is required (prefer /dev/serial/by-id/...)" >&2; exit 2; }
	$(MAKE) benchmark BENCH=$(BENCH) ITERATIONS=$(ITERATIONS) \
		VALIDATION=$(VALIDATION) CLOCK_HZ=$(CLOCK_HZ) PYTHON=$(PYTHON)
	$(PYTHON) ./loadprog.py $(BENCH_ELF) --port "$(PORT)" \
		--log "$(LOG)" --timeout $(TIMEOUT)

verify-uart:
	$(PYTHON) ./check_uart.py

verify-loader: benchmark
	$(PYTHON) ./check_loader.py $(BENCH_TEST) --expected-errors $(EXPECTED_ERRORS)

verify-host:
	$(PYTHON) ./tests/test_loadprog.py

verify-mem:
	$(PYTHON) -m unittest discover -s tests -p 'test_mkmem.py' -v

verify-bram:
	$(PYTHON) ./check_bram.py $(BRAM_TEST) \
		$(if $(EXPECTED_CYCLES),--expected-cycles $(EXPECTED_CYCLES),)

# ---- Cleaning ---------------------------------------------------------------
# clean      -- just $(TOP)'s outputs, so other tops' bitstreams survive
# clean-mem  -- the generated program images
# clean-all  -- everything this directory generates (tens of MB): every top's
#               netlist/packed netlist/bitstream, every tool log, the formal
#               work directories and the area baselines
#
# Sources are never touched: *.v *.sv *.f *.cst *.py *.md, and formal/*.sby
# and formal/*.sv (only formal/<task>/ work DIRECTORIES are removed).
clean:
	rm -f $(JSON) $(PACK_JSON) $(BITSTREAM)

clean-all: clean-mem
	@echo "Removing generated files in $(CURDIR):"
	@ls -1 *.json *.fs *.log 2>/dev/null | sed 's/^/    /' || true
	@ls -d formal/*/ 2>/dev/null | sed 's/^/    /' || true
	@rm -f *.json *.fs *.log
	@rm -rf formal/*/
	@echo "Done. Sources untouched."

# ---- Per-module area report -------------------------------------------------
# Ranks every module by LUT usage so area work can be aimed rather than
# guessed. Always runs synthesis to completion: cell counts taken before
# techmap do NOT predict post-ABC9 LUTs (shrinking the fetch queue once looked
# like -2,771 cells pre-map and turned out to be +2,750 LUTs after).
#
#   make area                     -> rank modules, print the budget verdict
#   make area ARGS="--save b.json"    -> record a baseline
#   make area ARGS="--compare b.json" -> per-module delta vs that baseline
# FILELIST defaults to blink.f for the other targets, which is not what you
# want here -- area work is always about the CPU.
AREA_FILELIST ?= cpu_top_filelist.f
area:
	./area_report.py --filelist $(AREA_FILELIST) $(ARGS)

clean-mem:
	rm -f imem_init.hex dmem_init.hex dmem_init_b*.hex imem_init_b*.hex

.PHONY: check synth bitstream flash flash-nv clean clean-all clean-mem mem area \
	benchmark benchmark-mem benchmark-bitstream benchmark-flash \
	benchmark-flash-nv benchmark-upload verify-uart verify-loader verify-host \
	verify-mem verify-bram
