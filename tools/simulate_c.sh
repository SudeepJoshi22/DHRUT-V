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

# Benchmark defaults are explicit; ordinary C tests retain random timing.
BENCHMARK=0
for src in "${C_SOURCES[@]}"; do
    case "$(realpath "$src")" in
        "$TESTS_DIR/bench/"*) BENCHMARK=1 ;;
    esac
done
if [ "$BENCHMARK" = 1 ]; then
    export MEM_STALL_MODE=${MEM_STALL_MODE:-fixed}
else
    export MEM_STALL_MODE=${MEM_STALL_MODE:-random}
fi
case "$MEM_STALL_MODE" in
    fixed|zero|random) ;;
    *) echo "Invalid MEM_STALL_MODE: $MEM_STALL_MODE" >&2; exit 1 ;;
esac

TEST_OUT_DIR=$BUILD_DIR/$TEST_NAME
ELF=$TEST_OUT_DIR/$TEST_NAME.elf
HEX=$TEST_OUT_DIR/$TEST_NAME.hex
DIS=$TEST_OUT_DIR/$TEST_NAME.dis

# ----------------------------------------
# BUILD
# ----------------------------------------
mkdir -p "$TEST_OUT_DIR"
# A failed rebuild/reference run must not leave an old PASS report usable.
rm -f "$TEST_OUT_DIR/simulation.log"

echo "▶ Building C test: $TEST_NAME"
echo "  Sources: ${C_SOURCES[*]}"
echo "  Output dir: $TEST_OUT_DIR"

# -DCLOCKS_PER_SEC=1 makes one "second" equal one cycle. CoreMark's
# core_main.c gates on `time_in_secs(total_time) < 10` and increments
# total_errors when it fails. One-iteration simulation is a correctness check,
# not a valid-duration score; this explicitly bypasses that duration check.
# It also supplies the symbol at all: CLOCKS_PER_SEC comes from
# <time.h>, which this freestanding build does not have. Dhrystone ignores it.
# See tests/bench/coremark/NOTICE.md.
BUILD_COMMAND=(riscv-none-elf-gcc -march=rv32im_zicsr -mabi=ilp32 \
    -O2 -ffreestanding -fno-stack-protector -fno-builtin \
    -DCLOCKS_PER_SEC=1 \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
    "${EXTRA_CFLAGS[@]}" \
    -T "$TESTS_DIR/linker_c.ld" \
    "$TESTS_DIR/crt0.S" "${C_SOURCES[@]}" \
    -lgcc -o "$ELF")
"${BUILD_COMMAND[@]}"

# Keep the actual command and implementation hashes beside each result.
python3 - "$ROOT_DIR" "$ELF" "${BUILD_COMMAND[@]}" <<'PY'
import hashlib, json, os, pathlib, subprocess, sys
root, elf = map(pathlib.Path, sys.argv[1:3])
paths = {root / arg for arg in sys.argv[3:] if pathlib.Path(arg).is_file()}
for folder in ["rtl", "test_bench", "tests/bench"]:
    paths.update(p for p in (root / folder).rglob("*")
                 if p.suffix in {".sv", ".py", ".c", ".h"})
paths.update([root / "tools/simulate_c.sh", root / "tools/pyUVM/Makefile"])
metadata = {
    "compiler": subprocess.check_output([sys.argv[3], "--version"], text=True).splitlines()[0],
    "command": sys.argv[3:],
    "revision": subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
    "dirty": bool(subprocess.check_output(["git", "-C", str(root), "status", "--porcelain"])),
    "memory_mode": os.environ["MEM_STALL_MODE"],
    "cpu_trace": os.environ.get("CPU_TRACE", "1"),
    "waves": os.environ.get("WAVES", "1"),
    "elf_sha256": hashlib.sha256(elf.read_bytes()).hexdigest(),
    "source_sha256": {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in sorted(paths) if p.is_relative_to(root) and p != elf},
}
elf.with_name("build.json").write_text(json.dumps(metadata, indent=2) + "\n")
PY

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

SPIKE_STATUS=0
timeout "${SPIKE_TIMEOUT:-60}" spike -l --log-commits --isa=rv32im_zicsr -m0x80000000:0x10000 "$ELF" > "$SPIKE_LOG" 2>&1 || SPIKE_STATUS=$?
if [ "$SPIKE_STATUS" != 0 ]; then
    echo "Spike failed or timed out (exit $SPIKE_STATUS): $SPIKE_LOG" >&2
    exit 1
fi

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
if [ "${CPU_TRACE:-1}" = 0 ]; then
    rm -f "$CPU_TRACE_FILE" "$CPU_DEEP_TRACE_FILE"
fi

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
