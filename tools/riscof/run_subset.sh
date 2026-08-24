#!/usr/bin/env bash
# tools/riscof/run_subset.sh
#
# Run a SUBSET of the riscof RV32I compliance suite in one riscof
# invocation. The full regression is the authoritative gate, but it is far
# too slow to sit in a per-change dev loop; this gives a fast, targeted
# signal during development. Run the full suite (tools/riscof/config.ini)
# before declaring a feature done.
#
# Usage:
#   ./run_subset.sh branch            # preset group (see GROUPS below)
#   ./run_subset.sh jal jalr beq      # explicit test-name prefixes
#   ./run_subset.sh --list            # show preset groups
#
# Test names are matched as prefixes, so "beq" picks up beq-01.S etc.

set -e

cd "$(dirname "$0")"

CONFIG="config.ini"
SUITE="riscv-arch-test/riscv-test-suite/rv32i_m/I/src"
ENV="riscv-arch-test/riscv-test-suite/env"
WORK_DIR="riscof_work"
TMP_YAML="subset_test.yaml"

# Preset groups, keyed to the part of the pipeline a change touches.
# Keep these small - the point is a fast loop, not coverage.
group_branch="jal jalr beq bne blt bge bltu bgeu"
group_mem="lb lh lw lbu lhu sb sh sw"
group_alu="add addi sub and andi or ori xor xori slt slti sltu sltiu"
group_shift="sll slli srl srli sra srai"
group_upper="lui auipc"
group_smoke="add addi jal beq lw sw"

if [ $# -lt 1 ] || [ "$1" = "--list" ]; then
    echo "Preset groups:"
    echo "  smoke   : $group_smoke"
    echo "  branch  : $group_branch"
    echo "  mem     : $group_mem"
    echo "  alu     : $group_alu"
    echo "  shift   : $group_shift"
    echo "  upper   : $group_upper"
    echo
    echo "Usage: $0 <group|test names...>"
    exit 0
fi

# Resolve a preset group name, else treat args as literal test prefixes
case "$1" in
    smoke)  TESTS="$group_smoke" ;;
    branch) TESTS="$group_branch" ;;
    mem)    TESTS="$group_mem" ;;
    alu)    TESTS="$group_alu" ;;
    shift)  TESTS="$group_shift" ;;
    upper)  TESTS="$group_upper" ;;
    *)      TESTS="$*" ;;
esac

if [ -f "../../venv/bin/activate" ]; then
    source "../../venv/bin/activate"
else
    echo "❌ Error: Virtual environment not found at ../../venv/bin/activate"
    exit 1
fi

echo "▶ Subset: $TESTS"
echo "▶ Generating/Updating master test list..."
riscof testlist --config "$CONFIG" --suite "$SUITE" --env "$ENV" --work-dir "$WORK_DIR"

echo "▶ Selecting matching tests..."
TESTS="$TESTS" python3 <<'EOF'
import os
import sys
import yaml

wanted = os.environ["TESTS"].split()

with open("riscof_work/test_list.yaml") as f:
    full_list = yaml.safe_load(f)

selected = {}
for path, data in full_list.items():
    name = path.rsplit("/", 1)[-1]
    stem = name[:-2] if name.endswith(".S") else name
    # prefix match so "beq" selects beq-01, and exclude what the DUT
    # can't support (mirrors filter_testlist.py's exclusions)
    if "/pmp/" in path or name.startswith("misalign"):
        continue
    for w in wanted:
        if stem == w or stem.startswith(w + "-"):
            selected[path] = data
            break

if not selected:
    print(f"❌ No tests matched: {wanted}")
    sys.exit(1)

for p in sorted(selected):
    print(f"   • {p.rsplit('/', 1)[-1]}")
print(f"   ({len(selected)} tests)")

with open("subset_test.yaml", "w") as f:
    yaml.dump(selected, f)
EOF

echo "▶ Running RISCOF subset..."
riscof run --no-browser --config "$CONFIG" --testfile "$TMP_YAML" --suite "$SUITE" --env "$ENV" --work-dir "$WORK_DIR"

echo "✔ Subset finished. (Full regression is still the gate before declaring a feature done.)"
