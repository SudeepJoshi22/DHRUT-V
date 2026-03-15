#!/usr/bin/env bash
set -e

# ----------------------------------------
# CONFIG
# ----------------------------------------
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TESTS_DIR=$ROOT_DIR/tests
ASM_DIR=$TESTS_DIR/asm
BUILD_DIR=$TESTS_DIR/build
SIM_DIR=$ROOT_DIR/tools/pyUVM
REPO_ROOT=$ROOT_DIR

# ----------------------------------------
# PARSE ARGS
# ----------------------------------------
if [ $# -lt 1 ]; then
    echo "Usage: $0 <test_name_no_ext> [seed]"
    exit 1
fi

TEST_NAME=$1
SEED=$2

S_FILE=$ASM_DIR/$TEST_NAME.S
ELF=$BUILD_DIR/$TEST_NAME.elf
HEX=$BUILD_DIR/$TEST_NAME.hex
DIS=$BUILD_DIR/$TEST_NAME.dis

# ----------------------------------------
# BUILD
# ----------------------------------------
mkdir -p $BUILD_DIR

echo "▶ Building test: $TEST_NAME"
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
    -T $TESTS_DIR/linker.ld \
    $S_FILE -o $ELF

riscv-none-elf-objcopy -O verilog $ELF $HEX
riscv-none-elf-objdump -D -M numeric,no-aliases $ELF > $DIS

echo "✔ Build complete:"
echo "  ELF: $ELF"
echo "  HEX: $HEX"
echo "  DIS: $DIS"

# ----------------------------------------
# VERIFY WITH SPIKE
# ----------------------------------------
SPIKE_LOG=$BUILD_DIR/$TEST_NAME.spike.log
echo "▶ Verifying test logic with Spike (Detailed Log: $SPIKE_LOG)"

# -l: Generate execution log
# --log-commits: Log register commits
# 2>&1: Redirect all output to log file
spike -l --log-commits --isa=rv32i -m0x80000000:0x10000 "$ELF" > "$SPIKE_LOG" 2>&1 || true

# Check for success in the generated log
# We check if a write of '1' occurred to the tohost address (0x80001000)
if grep -q "mem 0x80001000 0x00000001" "$SPIKE_LOG"; then
    echo "✅ Spike verification PASSED (tohost=1 detected in trace)"
elif grep -q "tohost = 0000000000000001" "$SPIKE_LOG" || grep -q "tohost = 1" "$SPIKE_LOG"; then
    echo "✅ Spike verification PASSED (tohost=1 detected in summary)"
else
    echo "❌ Spike verification FAILED!"
    echo "Check log for details: $SPIKE_LOG"
    exit 1
fi

# ----------------------------------------
# EXPORT ENV VARS
# ----------------------------------------
export TEST_HEX=$HEX
export TEST_ELF=$ELF
export CYCLE_TIMEOUT=10000
export COCOTB_LOG_LEVEL=INFO

# Handle Seed
if [ -n "$SEED" ]; then
    echo "▶ Using fixed seed: $SEED"
    export COCOTB_RANDOM_SEED=$SEED
else
    echo "▶ Using random seed (default cocotb behavior)"
fi

# ----------------------------------------
# RUN SIMULATION
# ----------------------------------------
echo "▶ Running simulation (Verilator)"
cd $SIM_DIR
make clean
make SIM=verilator LOG_LEVEL=DEBUG COCOTB_TEST_MODULES=run_test
