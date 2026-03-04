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
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
    -T $TESTS_DIR/linker.ld \
    $S_FILE -o $ELF

riscv64-unknown-elf-objcopy -O verilog $ELF $HEX
riscv64-unknown-elf-objdump -D -M numeric,no-aliases $ELF > $DIS

echo "✔ Build complete:"
echo "  ELF: $ELF"
echo "  HEX: $HEX"
echo "  DIS: $DIS"

# ----------------------------------------
# EXPORT ENV VARS
# ----------------------------------------
export TEST_HEX=$HEX
export TEST_ELF=$ELF
export TOHOST_ADDR=0x80001000
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
