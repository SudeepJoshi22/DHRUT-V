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

RISCV_PREFIX=riscv64-unknown-elf
ARCH=rv32i
ABI=ilp32

# ----------------------------------------
# ARG CHECK
# ----------------------------------------
if [ $# -ne 1 ]; then
    echo "Usage: $0 <test_name>"
    echo "Example: $0 add"
    exit 1
fi

TEST_NAME=$1
ASM_FILE=$ASM_DIR/${TEST_NAME}.S

if [ ! -f "$ASM_FILE" ]; then
    echo "ERROR: Test not found: $ASM_FILE"
    exit 1
fi

mkdir -p $BUILD_DIR

ELF=$BUILD_DIR/${TEST_NAME}.elf
HEX=$BUILD_DIR/${TEST_NAME}.hex
DIS=$BUILD_DIR/${TEST_NAME}.dis

echo "▶ Building test: $TEST_NAME"

# ----------------------------------------
# COMPILE ASM → ELF
# ----------------------------------------
$RISCV_PREFIX-gcc \
  -march=$ARCH -mabi=$ABI \
  -nostdlib -nostartfiles \
  -T $TESTS_DIR/linker.ld \
  $ASM_FILE \
  -o $ELF

# ----------------------------------------
# ELF → HEX
# ----------------------------------------
$RISCV_PREFIX-objcopy \
  -O verilog \
  $ELF $HEX

# ----------------------------------------
# ELF → DISASSEMBLY (debug)
# ----------------------------------------
$RISCV_PREFIX-objdump \
  -D -M numeric,no-aliases \
  $ELF > $DIS

echo "✔ Build complete:"
echo "  ELF: $ELF"
echo "  HEX: $HEX"
echo "  DIS: $DIS"

# ----------------------------------------
# EXPORT TO SIM
# ----------------------------------------
export TEST_HEX=$HEX
export COCOTB_LOG_LEVEL=INFO

# ----------------------------------------
# RUN SIMULATION
# ----------------------------------------
echo "▶ Running simulation (Verilator)"
cd $SIM_DIR
make clean
make SIM=verilator LOG_LEVEL=DEBUG

