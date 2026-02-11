# DHRUT-V

A fully pipelined, in-order superscalar RV32I RISC-V core written in SystemVerilog.

Designed for learning, verification, FPGA/ASIC exploration, and as a foundation for further extensions.

**Doom port in progress.**

## Features

- 5-stage pipeline: Fetch → Decode → Issue → Execute (ALU/LSU) → Retire
- Full RV32I base integer ISA support
- Hazard resolution with operand forwarding (ALU, Retire, LSU)
- Early branch resolution in Issue stage
- Load-Store Unit with back-pressure and stall propagation
- Single-issue dispatch to ALU or LSU
- Architectural Register File (ARF) inside Issue stage
- Verification-ready design with pyUVM testbench support

## Current Status

- Basic pipeline bring-up complete
- All RV32I instructions supported
- Forwarding, stalls, and branch handling working
- Doom port in progress (requires M extension + CSR support)

## Directory Structure

DHRUT-V/
├── rtl/                    # Core RTL and interfaces
│   ├── legacy/             # older/previous versions
│   └── ...                 # pipeline modules, interfaces, packages
├── test_bench/             # pyUVM testbench environment
│   └── run_test.py
├── tests/                  # Assembly tests & build artifacts
│   ├── asm/                # assembly source files
│   ├── build/              # compiled binaries
│   └── linker.ld           # linker script
├── tools/                  # Build, simulation & verification scripts
│   ├── install.sh          # one-click tool setup
│   ├── lint.sh             # RTL linting
│   ├── simulate.sh         # simulation launcher
├── LICENSE
├── README.md

## Getting Started

### Prerequisites

- Verilator
- RISC-V GNU Toolchain (`riscv64-unknown-elf-gcc`)
- Spike (RISC-V ISA simulator)
- Python 3 + virtualenv with `cocotb`, `pyuvm`, `find_libpython`, `PyYAML`

### Setup Environment

```bash
# Install tools (toolchain, Spike, Verilator)
./tools/install.sh
```

### Activate Python environment (cocotb + pyUVM)
```bash
source ~/riscv_pyenv/bin/activate   # or wherever your venv is
```

Lint RTL
```bash
./tools/lint.sh
```
Simulate a Test
```bash
# Run a specific test
./tools/simulate.sh <test-name>
```
```bash
# Example
./tools/simulate.sh test_load_use
```

## Roadmap

- Add M extension (mul/div)
- Add F extension
- Implement Zicsr (CSRs + interrupts)
- Other Performance Enhacements
- Complete Doom port (bare-metal)
- FPGA synthesis
