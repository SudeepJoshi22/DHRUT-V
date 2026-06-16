#!/usr/bin/env bash
# Compile and run UVM tests with Verilator
# Usage: ./tools/uvm_compile.sh [test_name] [--run]
#   test_name: name of the test file in test_bench/uvm/ (without .sv extension)
#   --run:     run the simulation after successful compilation

set -euo pipefail

# Source the environment to get UVM_HOME and other paths
if [ -f "$(dirname "$0")/../venv/bin/activate" ]; then
    source "$(dirname "$0")/../venv/bin/activate"
fi

# Default values
TEST_NAME="hello_world"
RUN_AFTER_COMPILE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --run)
            RUN_AFTER_COMPILE=true
            shift
            ;;
        --test)
            TEST_NAME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [test_name] [--run]"
            echo "  test_name:  name of test file in test_bench/uvm/ (default: hello_world)"
            echo "  --run:      run simulation after compilation"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            # Positional argument = test name
            TEST_NAME="$1"
            shift
            ;;
    esac
done

# Set UVM_HOME if not already set
if [ -z "${UVM_HOME:-}" ]; then
    export UVM_HOME="$(cd "$(dirname "$0")/.." && pwd)/tools/uvm-verilator/src"
fi

# Verify UVM_HOME exists
if [ ! -d "$UVM_HOME" ]; then
    echo "Error: UVM_HOME directory not found: $UVM_HOME"
    echo "Please ensure the uvm-verilator repository is cloned in tools/"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_FILE="$REPO_ROOT/test_bench/uvm/${TEST_NAME}.sv"
OBJ_DIR="$REPO_ROOT/obj_dir"

# Verify test file exists
if [ ! -f "$TEST_FILE" ]; then
    echo "Error: Test file not found: $TEST_FILE"
    echo "Available tests:"
    ls "$REPO_ROOT/test_bench/uvm/"*.sv 2>/dev/null | xargs -n1 basename | sed 's/.sv//' | sed 's/^/  /'
    exit 1
fi

echo "============================================"
echo "  UVM Compile & Run"
echo "============================================"
echo "  Test:    $TEST_NAME"
echo "  File:    $TEST_FILE"
echo "  UVM:     $UVM_HOME"
echo "  Output:  $OBJ_DIR"
echo "============================================"

# Compile with Verilator
# --binary: compile to binary executable (implies --cc --exe --build)
# Note: UVM requires DPI for run_test() — do NOT use +define+UVM_NO_DPI
verilator \
    --sv \
    --binary \
    --top-module tb_top \
    --Mdir "$OBJ_DIR" \
    --error-limit 5 \
    --hierarchical \
    -j 4 \
    -Wall \
    -Wno-DECLFILENAME \
    -Wno-IMPORTSTAR \
    -Wno-WIDTHTRUNC \
    --timescale 1ns/1ns \
    +define+UVM_REPORT_DISABLE_FILE_LINE \
    +define+SVA_ON \
    +incdir+"$UVM_HOME" \
    +incdir+"$UVM_HOME/dpi" \
    "$UVM_HOME/uvm_pkg.sv" \
    "$TEST_FILE"

if [ $? -eq 0 ]; then
    echo ""
    echo "Compilation successful!"
    echo "  Binary: $OBJ_DIR/Vtb_top"
    echo ""

    if $RUN_AFTER_COMPILE; then
        echo "Running simulation..."
        echo "============================================"
        cd "$REPO_ROOT"
        "$OBJ_DIR/Vtb_top"
        echo "============================================"
        echo "Simulation finished."
    else
        echo "To run the simulation:"
        echo "  ./obj_dir/Vtb_top"
        echo ""
        echo "Or use --run to compile and run in one step:"
        echo "  $0 $TEST_NAME --run"
    fi
else
    echo ""
    echo "Compilation failed!"
    exit 1
fi
