# Variables
RTL_DIR := rtl/
PROGRAMS_DIR := programs/
TESTBENCH_DIR := test_bench/
TEST := test
PYTHON_SCRIPT := programs/extract.py

#DATA_MEM_ADDRESS := 0
#INSTR_MEM_ADDRESS := 0

VERILOG_FILE := rtl/top_module.v
TEST_BENCH := test_bench/tb_top_module.v


init:
	bash tools/install_tools.sh
	

core: $(PROGRAMS_DIR)$(TEST).elf $(PROGRAMS_DIR)$(TEST).S
	@echo "YOUR PROGRAM IS EXECUTING UNDER THE SYMPHONY OF"
	@echo "---______ _   _ ______ _   _ _____      _   _---"
	@echo "---|  _  \ | | || ___ \ | | |_   _|    | | | |---"
	@echo "---| | | | |_| || |_/ / | | | | |______| | | |---"
	@echo "---| | | |  _  ||    /| | | | | |______| | | |---"
	@echo "---| |/ /| | | || |\ \| |_| | | |      \ \_/ /---"
	@echo "---|___/ \_| |_/\_| \_|\___/  \_/       \___/---"

	@echo "Cleaning the log files..."
	@echo "Dividing the memory file into instructon memory and data memory file"
	python3 $(PYTHON_SCRIPT)
	@echo "Configuring RTL..."
	DATA_MEM_ADDRESS=$$(grep -m 1 -oP '(?<=@)[0-9A-F]+' programs/memory.hex); \
	INSTR_MEM_ADDRESS=$$(grep -m 2 -oP '(?<=@)[0-9A-F]+' programs/memory.hex | tail -n 1); \
	sed -i "s/\`define PC_RESET .*/\`define PC_RESET 32'h$$INSTR_MEM_ADDRESS/" rtl/parameters.vh; \
	sed -i "s/\`define DATA_START .*/\`define DATA_START 32'h$$DATA_MEM_ADDRESS/" rtl/parameters.vh

	@echo "Executing The Program on Spike..."
	spike --log-commits --log  $(TEST)_spike.dump --isa=rv32i $(PROGRAMS_DIR)$(TEST).elf
	@echo "Compiling Verilog files..."
	iverilog -o output.vvp $(TEST_BENCH) $(VERILOG_FILE)
	vvp output.vvp
	@echo "Generating waveform..."
	#gtkwave waveform.vcd &
	
$(PROGRAMS_DIR)$(TEST).S:
	rm -f *.vvp *.log *.vcd $(PROGRAMS_DIR)*.elf $(PROGRAMS_DIR)*.hex $(PROGRAMS_DIR)*.dis $(PROGRAMS_DIR)*.dump $(PROGRAMS_DIR)*.mem
	riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -T $(PROGRAMS_DIR)linker.ld $(PROGRAMS_DIR)$(TEST).S -o $(PROGRAMS_DIR)$(TEST).elf
	riscv64-unknown-elf-objdump -M no-aliases -M numeric -D $(PROGRAMS_DIR)$(TEST).elf > $(PROGRAMS_DIR)$(TEST).dis
	riscv64-unknown-elf-objcopy -O verilog $(PROGRAMS_DIR)$(TEST).elf $(PROGRAMS_DIR)memory.hex

$(PROGRAMS_DIR)$(TEST).elf:
	rm -f *.vvp *.log *.vcd $(PROGRAMS_DIR)*.elf $(PROGRAMS_DIR)*.hex $(PROGRAMS_DIR)*.dis $(PROGRAMS_DIR)*.dump $(PROGRAMS_DIR)*.mem
	riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -T $(PROGRAMS_DIR)linker.ld $(PROGRAMS_DIR)$(TEST).S -o $(PROGRAMS_DIR)$(TEST).elf
	riscv64-unknown-elf-objdump -M no-aliases -M numeric -D $(PROGRAMS_DIR)$(TEST).elf > $(PROGRAMS_DIR)$(TEST).dis
	riscv64-unknown-elf-objcopy -O verilog $(PROGRAMS_DIR)$(TEST).elf $(PROGRAMS_DIR)memory.hex
	
compile: $(TESTBENCH_DIR)$(TB).v $(RTL_DIR)$(DESIGN).v
	@echo "Compiling Verilog files..."
	iverilog -o output.vvp $(TESTBENCH_DIR)$(TB).v $(RTL_DIR)$(DESIGN).v
	vvp output.vvp
	@echo "Generating waveform..."
	gtkwave waveform.vcd &

clean:
	@echo "Cleaning up..."
	rm -f *.vvp *.log *.vcd $(PROGRAMS_DIR)*.elf $(PROGRAMS_DIR)*.hex $(PROGRAMS_DIR)*.dis *.dump $(PROGRAMS_DIR)*.mem

.PHONY: all core compile clean
