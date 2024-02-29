# Variables
RTL_DIR := rtl/
PROGRAMS_DIR := programs/
TEST_PROGRAM := test
PYTHON_SCRIPT := programs/extract.py

VERILOG_FILE := rtl/top_module.v
TEST_BENCH := test_bench/tb_top_module.v


init:
	bash tools/install_tools.sh
	

core: $(PROGRAMS_DIR)memory.hex
	@echo "Cleaning the log files..."
	@echo "Dividing the memory file into instructon memory and data memory file"
	python3 $(PYTHON_SCRIPT)
	@echo "Executing The Program on Spike..."
	spike --log-commits --log  $(TEST_PROGRAM)_spike.dump --isa=rv32i $(PROGRAMS_DIR)$(TEST_PROGRAM).elf
	@echo "Compiling Verilog files..."
	iverilog -o output.vvp $(TEST_BENCH) $(VERILOG_FILE)
	vvp output.vvp
	@echo "Generating waveform..."
	#gtkwave waveform.vcd &
	
$(PROGRAMS_DIR)memory.hex:
	rm -f *.vvp *.log *.vcd $(PROGRAMS_DIR)*.elf $(PROGRAMS_DIR)*.hex $(PROGRAMS_DIR)*.dis $(PROGRAMS_DIR)*.dump $(PROGRAMS_DIR)*.mem
	riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -T $(PROGRAMS_DIR)linker.ld $(PROGRAMS_DIR)$(TEST_PROGRAM).S -o $(PROGRAMS_DIR)$(TEST_PROGRAM).elf
	riscv64-unknown-elf-objdump -D $(PROGRAMS_DIR)$(TEST_PROGRAM).elf > $(PROGRAMS_DIR)$(TEST_PROGRAM).dis
	riscv64-unknown-elf-objcopy -O verilog $(PROGRAMS_DIR)$(TEST_PROGRAM).elf $(PROGRAMS_DIR)memory.hex
	
compile: $(TB) $(DESIGN)
	@echo "Compiling Verilog files..."
	iverilog -o output.vvp $(TB) $(DESIGN)
	vvp output.vvp
	@echo "Generating waveform..."
	gtkwave waveform.vcd

clean:
	@echo "Cleaning up..."
	rm -f *.vvp *.log *.vcd $(PROGRAMS_DIR)*.elf $(PROGRAMS_DIR)*.hex $(PROGRAMS_DIR)*.dis *.dump $(PROGRAMS_DIR)*.mem

.PHONY: all core compile clean
