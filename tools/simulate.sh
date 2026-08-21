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

# Per-test output directory: every artifact for this test (elf/hex/dis,
# spike log, cocotb simulation.log, cpu trace logs, waveform) lands here
# instead of being scattered across tests/build/ and tools/pyUVM/.
TEST_OUT_DIR=$BUILD_DIR/$TEST_NAME

S_FILE=$ASM_DIR/$TEST_NAME.S
ELF=$TEST_OUT_DIR/$TEST_NAME.elf
HEX=$TEST_OUT_DIR/$TEST_NAME.hex
DIS=$TEST_OUT_DIR/$TEST_NAME.dis

# ----------------------------------------
# BUILD
# ----------------------------------------
mkdir -p $TEST_OUT_DIR

echo "▶ Building test: $TEST_NAME"
echo "  Output dir: $TEST_OUT_DIR"
riscv-none-elf-gcc -march=rv32i_zicsr -mabi=ilp32 \
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
SPIKE_LOG=$TEST_OUT_DIR/$TEST_NAME.spike.log
echo "▶ Verifying test logic with Spike (Detailed Log: $SPIKE_LOG)"

# -l: Generate execution log
# --log-commits: Log register commits
# 2>&1: Redirect all output to log file
spike -l --log-commits --isa=rv32i_zicsr -m0x80000000:0x10000 "$ELF" > "$SPIKE_LOG" 2>&1 || true

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

# Route cocotb/pyuvm run outputs (simulation.log, cpu_trace.log,
# cpu_deep_trace.log) into the same per-test directory as the
# compile-step artifacts above.
export SIMULATION_LOG_FILE=$TEST_OUT_DIR/simulation.log
export CPU_TRACE_FILE=$TEST_OUT_DIR/cpu_trace.log
export CPU_DEEP_TRACE_FILE=$TEST_OUT_DIR/cpu_deep_trace.log

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

# ----------------------------------------
# COLLECT REMAINING ARTIFACTS
# ----------------------------------------
# The waveform dump (dump.vcd) is written by tb_top.sv with a hardcoded
# relative filename, so it always lands in $SIM_DIR (make's cwd) rather
# than respecting an env var. Move it (and any stray simulation.log that
# fell back to the default path) into the per-test dir so nothing is left
# scattered in $SIM_DIR after the run.
for f in dump.vcd dump.fst simulation.log; do
    if [ -f "$SIM_DIR/$f" ]; then
        mv "$SIM_DIR/$f" "$TEST_OUT_DIR/$f"
    fi
done

echo "✔ All artifacts for '$TEST_NAME' collected in: $TEST_OUT_DIR"
