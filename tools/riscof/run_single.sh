#!/usr/bin/env bash
# tools/riscof/run_single.sh
# Usage: ./run_single.sh <test_name> (e.g., andi-01)

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <test_name_no_ext>"
    echo "Example: $0 andi-01"
    exit 1
fi

TEST_NAME=$1
# Append .S if not present
if [[ ! "$TEST_NAME" == *.S ]]; then
    TEST_NAME="${TEST_NAME}.S"
fi

# Configuration paths
CONFIG="config.ini"
SUITE="riscv-arch-test/riscv-test-suite/rv32i_m/I/src"
ENV="riscv-arch-test/riscv-test-suite/env"
WORK_DIR="riscof_work"
TMP_YAML="single_test.yaml"

# Change to the script's directory to ensure relative paths work
cd "$(dirname "$0")"

# Activate the virtual environment
if [ -f "../../venv/bin/activate" ]; then
    source "../../venv/bin/activate"
else
    echo "❌ Error: Virtual environment not found at ../../venv/bin/activate"
    exit 1
fi

echo "▶ Generating/Updating master test list..."
riscof testlist --config "$CONFIG" --suite "$SUITE" --env "$ENV" --work-dir "$WORK_DIR"

echo "▶ Extracting entry for: $TEST_NAME"
# Use Python to robustly filter the YAML for just the requested test
python3 <<EOF
import yaml
import sys

with open('$WORK_DIR/test_list.yaml', 'r') as f:
    full_list = yaml.safe_load(f)

# Look for the test path that ends with the requested TEST_NAME
filtered_list = {}
for path, data in full_list.items():
    if path.endswith('/$TEST_NAME'):
        filtered_list[path] = data
        break

if not filtered_list:
    print(f"❌ Error: Test '$TEST_NAME' not found in $WORK_DIR/test_list.yaml")
    sys.exit(1)

with open('$TMP_YAML', 'w') as f:
    yaml.dump(filtered_list, f)
EOF

echo "▶ Running RISCOF for $TEST_NAME..."
riscof run --no-browser --config "$CONFIG" --testfile "$TMP_YAML" --suite "$SUITE" --env "$ENV" --work-dir "$WORK_DIR"

echo "✔ Execution finished."
