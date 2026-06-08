#!/usr/bin/env bash
# Simple script to compile SystemVerilog UVM tests with Verilator

# Source the environment to get UVM_HOME and other paths
if [ -f "$(dirname "$0")/../venv/bin/activate" ]; then
    source "$(dirname "$0")/../venv/bin/activate"
fi

# Default values
TEST_NAME="hello_world"
VERILATOR_OPTS="--sv --top-module tb_top --exe --build --Mdir obj_dir --error-limit 5 --hierarchical --coverage -j 4 -Wall --timescale 1ns/1ns +define+UVM_REPORT_DISABLE_FILE_LINE +define+UVM_NO_DPI +define+SVA_ON"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test)
            TEST_NAME="$2"
            shift 2
            ;;
        *)
            # Unknown option
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set UVM_HOME if not already set
if [ -z "$UVM_HOME" ]; then
    export UVM_HOME="$HOME/GitHub/DHRUT-V/tools/uvm-verilator/src"
fi

# Verify UVM_HOME exists
if [ ! -d "$UVM_HOME" ]; then
    echo "Error: UVM_HOME directory not found: $UVM_HOME"
    echo "Please ensure the uvm-verilator repository is cloned in tools/"
    exit 1
fi

# Set the test file path
TEST_FILE="test_bench/uvm/${TEST_NAME}.sv"
if [ ! -f "$TEST_FILE" ]; then
    echo "Error: Test file not found: $TEST_FILE"
    exit 1
fi

echo "Compiling UVM test: $TEST_FILE"
echo "Using UVM_HOME: $UVM_HOME"

# Run Verilator compilation
verilator $VERILATOR_OPTS \
    +incdir+$UVM_HOME \
    $UVM_HOME/uvm_pkg.sv \
    $TEST_FILE

if [ $? -eq 0 ]; then
    echo ""
    echo "Compilation successful!"
    echo "To run the simulation:"
    echo "  ./obj_dir/Vtb_top"
else
    echo "Compilation failed!"
    exit 1
fi