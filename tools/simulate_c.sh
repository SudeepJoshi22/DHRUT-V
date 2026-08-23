#!/usr/bin/env bash
set -e

# ----------------------------------------
# Bare-metal C program runner (parallel to simulate.sh, which only
# handles single-file tests/asm/*.S). Compiles crt0.S + one or more C
# sources against tests/linker_c.ld, verifies against Spike, then runs
# the same Verilator/cocotb flow.
# ----------------------------------------
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
TESTS_DIR=$ROOT_DIR/tests
BUILD_DIR=$TESTS_DIR/build
SIM_DIR=$ROOT_DIR/tools/pyUVM
REPO_ROOT=$ROOT_DIR

# ----------------------------------------
# PARSE ARGS
# ----------------------------------------
if [ $# -lt 2 ]; then
    echo "Usage: $0 <test_name> <c_source1> [c_source2 ...] [-- extra_cflags...]"
    echo "  e.g. $0 hello_cycles tests/c/hello_cycles.c"
    exit 1
fi

TEST_NAME=$1
shift

C_SOURCES=()
EXTRA_CFLAGS=()
PARSING_FLAGS=0
for arg in "$@"; do
    if [ "$arg" = "--" ]; then
        PARSING_FLAGS=1
        continue
    fi
    if [ "$PARSING_FLAGS" = "1" ]; then
        EXTRA_CFLAGS+=("$arg")
    else
        C_SOURCES+=("$arg")
    fi
done

TEST_OUT_DIR=$BUILD_DIR/$TEST_NAME
ELF=$TEST_OUT_DIR/$TEST_NAME.elf
HEX=$TEST_OUT_DIR/$TEST_NAME.hex
DIS=$TEST_OUT_DIR/$TEST_NAME.dis

# ----------------------------------------
# BUILD
# ----------------------------------------
mkdir -p "$TEST_OUT_DIR"

echo "▶ Building C test: $TEST_NAME"
echo "  Sources: ${C_SOURCES[*]}"
echo "  Output dir: $TEST_OUT_DIR"

riscv-none-elf-gcc -march=rv32i_zicsr -mabi=ilp32 \
    -O2 -ffreestanding -fno-stack-protector -fno-builtin \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
    "${EXTRA_CFLAGS[@]}" \
    -T "$TESTS_DIR/linker_c.ld" \
    "$TESTS_DIR/crt0.S" "${C_SOURCES[@]}" \
    -lgcc -o "$ELF"

riscv-none-elf-objcopy -O verilog "$ELF" "$HEX"
riscv-none-elf-objdump -D -M numeric,no-aliases "$ELF" > "$DIS"

echo "✔ Build complete:"
echo "  ELF: $ELF"
echo "  HEX: $HEX"
echo "  DIS: $DIS"

# ----------------------------------------
# VERIFY WITH SPIKE
# ----------------------------------------
SPIKE_LOG=$TEST_OUT_DIR/$TEST_NAME.spike.log
echo "▶ Verifying test logic with Spike (Detailed Log: $SPIKE_LOG)"

spike -l --log-commits --isa=rv32i_zicsr -m0x80000000:0x10000 "$ELF" > "$SPIKE_LOG" 2>&1 || true

# tohost's address moves depending on how big .text is (it's placed on
# the first 0x1000 boundary after .text - see tests/linker_c.ld), so
# resolve it from the ELF symbol table instead of hardcoding an address.
TOHOST_ADDR=$(riscv-none-elf-nm "$ELF" | awk '$3 == "tohost" {print $1}')

if [ -n "$TOHOST_ADDR" ] && grep -qi "mem 0x${TOHOST_ADDR} 0x00000001" "$SPIKE_LOG"; then
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
export CYCLE_TIMEOUT=${CYCLE_TIMEOUT:-1000000}
export COCOTB_LOG_LEVEL=INFO

export SIMULATION_LOG_FILE=$TEST_OUT_DIR/simulation.log
export CPU_TRACE_FILE=$TEST_OUT_DIR/cpu_trace.log
export CPU_DEEP_TRACE_FILE=$TEST_OUT_DIR/cpu_deep_trace.log

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
cd "$SIM_DIR"
make clean
make SIM=verilator LOG_LEVEL=DEBUG COCOTB_TEST_MODULES=run_test

# ----------------------------------------
# COLLECT REMAINING ARTIFACTS
# ----------------------------------------
for f in dump.vcd dump.fst simulation.log; do
    if [ -f "$SIM_DIR/$f" ]; then
        mv "$SIM_DIR/$f" "$TEST_OUT_DIR/$f"
    fi
done

echo "✔ All artifacts for '$TEST_NAME' collected in: $TEST_OUT_DIR"
