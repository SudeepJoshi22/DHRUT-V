#!/usr/bin/env bash
# Script to compile and run UVM tests with Verilator

# Source the environment
if [ -f "$(dirname "$0")/../venv/bin/activate" ]; then
    source "$(dirname "$0")/../venv/bin/activate"
fi

# Set default test name
TEST_NAME=${1:-hello_world}

# Set paths
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UVM_PKG="$REPO_ROOT/tools/verilator/test_regress/t/uvm/uvm_pkg_all_v2017_1_0_dpi.svh"
TEST_FILE="$REPO_ROOT/test_bench/uvm/${TEST_NAME}.sv"
OBJ_DIR="$REPO_ROOT/obj_dir"

# Check if UVM package exists
if [ ! -f "$UVM_PKG" ]; then
    echo "Error: UVM package not found at $UVM_PKG"
    exit 1
fi

# Check if test file exists
if [ ! -f "$TEST_FILE" ]; then
    echo "Error: Test file not found at $TEST_FILE"
    exit 1
fi

echo "Compiling UVM test: $TEST_NAME"
echo "Test file: $TEST_FILE"
echo "UVM package: $UVM_PKG"

# Compile with Verilator
verilator --sv --main --binary --build --cc \
  --Mdir "$OBJ_DIR" \
  --error-limit 5 \
  --hierarchical \
  --coverage \
  -j 4 \
  -Wall \
  --timescale 1ns/1ns \
  +define+UVM_REPORT_DISABLE_FILE_LINE \
  +define+UVM_NO_DPI \
  +define+SVA_ON \
  +incdir+"$REPO_ROOT/tools/verilator/test_regress/t/uvm" \
  "$UVM_PKG" \
  "$TEST_FILE"

# Check if compilation succeeded
if [ $? -eq 0 ]; then
    echo ""
    echo "Compilation successful!"
    echo "To run the simulation:"
    echo "  cd $REPO_ROOT && ./obj_dir/Vtb_top"
    echo ""
    echo "To run with waveform dumping (if enabled in test):"
    echo "  cd $REPO_ROOT && ./obj_dir/Vtb_top +verilator+rand+reset+2"
else
    echo ""
    echo "Compilation failed!"
    exit 1
fi