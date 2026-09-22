# Tang Nano 20K build, flash and UART workflow. See fpga/README.md.
# Requires OSS CAD Suite. Generate memory images before CPU synthesis.

DEVICE     = GW2AR-LV18QN88C8/I7
FAMILY     = GW2A-18C

# Find the cross compiler in this clone or the adjacent stable clone; fall back to PATH.
RISCV_BIN  := $(firstword $(wildcard ../tools/toolchain/xpack-riscv-none-elf-gcc-*/bin ../../DHRUT-V/tools/toolchain/xpack-riscv-none-elf-gcc-*/bin))
RISCV_PATH := $(if $(RISCV_BIN),$(abspath $(RISCV_BIN)):,)

# Place-and-route clock constraint matches the 27 MHz board oscillator.
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

# Read source files in dependency order using the SystemVerilog slang frontend.
BUILD_FILES = FILES=$$(grep -v '^[[:space:]]*\#' $(FILELIST) | grep -v '^[[:space:]]*$$' | tr '\n' ' ');

# Map to LUT4s without wide-LUT mux clusters.
SYNTH_OPTS ?= -nowidelut

check:
	$(BUILD_FILES) yosys -m slang -p "read_slang $$FILES --top $(TOP); synth_gowin -top $(TOP) $(SYNTH_OPTS); stat"

synth:
	$(BUILD_FILES) yosys -m slang -p "read_slang $$FILES --top $(TOP); synth_gowin -top $(TOP) $(SYNTH_OPTS) -json $(JSON); stat"

# Rebuild the netlist when the filelist, RTL or memory images change.
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

# These targets deliberately rebuild first. Use flash-cpu / flash-cpu-nv to
# load an already-existing CPU bitstream without running yosys or nextpnr.
flash: $(BITSTREAM)
	openFPGALoader -b tangnano20k $(BITSTREAM)

flash-nv: $(BITSTREAM)
	openFPGALoader -b tangnano20k -f $(BITSTREAM)

CPU_BITSTREAM ?= cpu_top.fs

flash-cpu:
	@test -f "$(CPU_BITSTREAM)" || { echo "CPU bitstream not found: $(CPU_BITSTREAM). Run benchmark-flash once first." >&2; exit 2; }
	openFPGALoader -b tangnano20k "$(CPU_BITSTREAM)"

flash-cpu-nv:
	@test -f "$(CPU_BITSTREAM)" || { echo "CPU bitstream not found: $(CPU_BITSTREAM). Run benchmark-flash once first." >&2; exit 2; }
	openFPGALoader -b tangnano20k -f "$(CPU_BITSTREAM)"

# Generate BRAM images from a test ELF/hex pair; report its tohost address.
TEST ?= add
TEST_DIR = ../tests/build/$(TEST)

mem:
	PATH="$(RISCV_PATH)$$PATH" ./mkmem.py $(TEST_DIR)/$(TEST).hex --elf $(TEST_DIR)/$(TEST).elf --outdir .

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
INTERACTIVE     ?= 1
BRAM_TEST       ?= dhrystone_edgefix
EXPECTED_CYCLES ?=
ELF             ?=
PROGRAM_NAME    ?= hello_uart
PROGRAM_SOURCES ?= examples/hello_uart.c
PROGRAM_CFLAGS  ?=

VALIDATION_ENABLED = $(filter 1 yes true,$(VALIDATION))
VALIDATION_ARG     = $(if $(VALIDATION_ENABLED),--validation,)
BENCH_SUFFIX       = $(if $(VALIDATION_ENABLED),_validation,)
BENCH_TEST         = $(BENCH)_hw_$(ITERATIONS)$(BENCH_SUFFIX)
BENCH_DIR          = ../tests/build/$(BENCH_TEST)
BENCH_ELF          = $(BENCH_DIR)/$(BENCH_TEST).elf
BENCH_HEX          = $(BENCH_DIR)/$(BENCH_TEST).hex
LOG                ?=
BENCH_LOG           = $(if $(LOG),$(LOG),$(BENCH_TEST).log)
ELF_LOG             = $(if $(LOG),$(LOG),$(notdir $(basename $(ELF))).log)
INTERACTIVE_ARG      = $(if $(filter 1 yes true,$(INTERACTIVE)),--interactive,)
PROGRAM_DIR         = ../tests/build/$(PROGRAM_NAME)
PROGRAM_ELF         = $(PROGRAM_DIR)/$(PROGRAM_NAME).elf
PROGRAM_HEX         = $(PROGRAM_DIR)/$(PROGRAM_NAME).hex

benchmark:
	PATH="$(RISCV_PATH)$$PATH" $(PYTHON) ./build_benchmark.py $(BENCH) --iterations $(ITERATIONS) \
		--clock-hz $(CLOCK_HZ) $(VALIDATION_ARG)

benchmark-mem: benchmark
	PATH="$(RISCV_PATH)$$PATH" ./mkmem.py $(BENCH_HEX) --elf $(BENCH_ELF) --outdir .

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
	PATH="$(RISCV_PATH)$$PATH" $(PYTHON) ./loadprog.py $(BENCH_ELF) --port "$(PORT)" \
		--log "$(BENCH_LOG)" --timeout $(TIMEOUT)

# Upload any already-linked bare-metal ELF. This changes BRAM contents over
# UART; it does not synthesize or reflash the FPGA.
elf-upload:
	@test -n "$(PORT)" || { echo "PORT is required (prefer /dev/serial/by-id/...)" >&2; exit 2; }
	@test -n "$(ELF)" || { echo "ELF=/path/to/program.elf is required" >&2; exit 2; }
	@test -f "$(ELF)" || { echo "ELF not found: $(ELF)" >&2; exit 2; }
	PATH="$(RISCV_PATH)$$PATH" $(PYTHON) ./loadprog.py "$(ELF)" --port "$(PORT)" \
		--log "$(ELF_LOG)" --timeout $(TIMEOUT) $(INTERACTIVE_ARG)

# Compile one or more freestanding C files for the resident RV32IM CPU. The
# public header supplies UART, cycle-counter and completion helpers.
program-build:
	@test -n "$(PROGRAM_NAME)" || { echo "PROGRAM_NAME is required" >&2; exit 2; }
	@test -n "$(PROGRAM_SOURCES)" || { echo "PROGRAM_SOURCES is required" >&2; exit 2; }
	@mkdir -p $(PROGRAM_DIR)
	PATH="$(RISCV_PATH)$$PATH" riscv-none-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -O2 \
		-ffreestanding -fno-stack-protector -fno-builtin -static \
		-mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
		-Iinclude $(PROGRAM_CFLAGS) -T ../tests/linker_c.ld \
		../tests/crt0.S $(PROGRAM_SOURCES) -lgcc -o $(PROGRAM_ELF)
	PATH="$(RISCV_PATH)$$PATH" riscv-none-elf-objcopy -O verilog $(PROGRAM_ELF) $(PROGRAM_HEX)
	PATH="$(RISCV_PATH)$$PATH" riscv-none-elf-size $(PROGRAM_ELF)

program-upload:
	@test -n "$(PORT)" || { echo "PORT is required (prefer /dev/serial/by-id/...)" >&2; exit 2; }
	$(MAKE) program-build PROGRAM_NAME=$(PROGRAM_NAME) \
		PROGRAM_SOURCES="$(PROGRAM_SOURCES)" PROGRAM_CFLAGS="$(PROGRAM_CFLAGS)"
	$(MAKE) elf-upload ELF=$(PROGRAM_ELF) PORT="$(PORT)" \
		LOG="$(if $(LOG),$(LOG),$(PROGRAM_NAME).log)" TIMEOUT=$(TIMEOUT) PYTHON=$(PYTHON)

# Interactive laptop-side launcher. Iterations are compiled into a fresh
# benchmark ELF for reproducibility, then that ELF is loaded over UART in
# seconds; FPGA synthesis is not involved.
console:
	@test -n "$(PORT)" || { echo "PORT is required (prefer /dev/serial/by-id/...)" >&2; exit 2; }
	@set -eu; \
	printf 'Program [dhrystone/coremark/elf]: '; read program; \
	case "$$program" in \
	  dhrystone|coremark) \
	    printf 'Iterations: '; read iterations; \
	    validation=0; \
	    if test "$$program" = coremark; then \
	      printf 'Validation seeds? [y/N]: '; read answer; \
	      case "$$answer" in y|Y|yes|YES) validation=1;; esac; \
	    fi; \
	    $(MAKE) benchmark-upload BENCH="$$program" ITERATIONS="$$iterations" \
	      VALIDATION="$$validation" PORT="$(PORT)" TIMEOUT="$(TIMEOUT)";; \
	  elf) \
	    printf 'ELF path: '; read elf; \
	    $(MAKE) elf-upload ELF="$$elf" PORT="$(PORT)" TIMEOUT="$(TIMEOUT)";; \
	  *) echo 'Expected dhrystone, coremark, or elf' >&2; exit 2;; \
	esac

terminal:
	@test -n "$(PORT)" || { echo "PORT is required (prefer /dev/serial/by-id/...)" >&2; exit 2; }
	$(PYTHON) ./loadprog.py --monitor --port "$(PORT)"

verify-uart:
	$(PYTHON) ./check_uart.py

verify-loader: benchmark
	PATH="$(RISCV_PATH)$$PATH" $(PYTHON) ./check_loader.py $(BENCH_TEST) --expected-errors $(EXPECTED_ERRORS)

verify-host:
	$(PYTHON) ./tests/test_loadprog.py

verify-mem:
	$(PYTHON) -m unittest discover -s tests -p 'test_mkmem.py' -v

verify-bram:
	PATH="$(RISCV_PATH)$$PATH" $(PYTHON) ./check_bram.py $(BRAM_TEST) \
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

# Report full-synthesis resource totals and per-module costs for the CPU.
AREA_FILELIST ?= cpu_top_filelist.f
area:
	./area_report.py --filelist $(AREA_FILELIST) $(ARGS)

clean-mem:
	rm -f imem_init.hex dmem_init.hex dmem_init_b*.hex imem_init_b*.hex

.PHONY: check synth bitstream flash flash-nv flash-cpu flash-cpu-nv clean clean-all clean-mem mem area \
	benchmark benchmark-mem benchmark-bitstream benchmark-flash \
	benchmark-flash-nv benchmark-upload verify-uart verify-loader verify-host \
	verify-mem verify-bram elf-upload program-build program-upload console terminal
