#!/usr/bin/env bash
# tools/lint.sh
# Quick Verilator linting check for the entire RTL design
# Usage: ./tools/lint.sh
#        ./tools/lint.sh --relaxed    (to suppress common warnings during early dev)

set -euo pipefail

# ----------------------------------------
# CONFIGURATION
# ----------------------------------------
ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
RTL_DIR="$ROOT_DIR/rtl"

# Source files - same pattern as your cocotb Makefile
RTL_SOURCES=(
    "$RTL_DIR/include"/*.sv
    "$RTL_DIR/interfaces"/*.sv
    "$RTL_DIR/pipeline"/*.sv
    "$RTL_DIR/tb_top.sv"
)

# Top module name (important for linting!)
TOP_MODULE="tb_top"

# ----------------------------------------
# ARGUMENTS / MODE
# ----------------------------------------
RELAXED=false
if [[ "${1:-}" == "--relaxed" || "${1:-}" == "-r" ]]; then
    RELAXED=true
    echo "→ Running in relaxed mode (common warnings suppressed)"
fi

# ----------------------------------------
# VERILATOR LINT COMMAND
# ----------------------------------------
VERILATOR_ARGS=(
    --lint-only
    -Wall
    -Wpedantic
    --timing
    --top-module "$TOP_MODULE"
    +1800-2023ext+sv          # modern SystemVerilog
    --assert                  # enable assertion checks
    --quiet-exit              # cleaner exit code behavior
)

# Common warnings we often want to keep even in relaxed mode:
# WIDTHTRUNC, WIDTHEXPAND, UNUSEDSIGNAL, UNDRIVEN, etc.

if $RELAXED; then
    # Suppress most annoying warnings during early development
    VERILATOR_ARGS+=(
        -Wno-WIDTH          # bit width mismatch (very common in decode/execute)
        -Wno-WIDTHTRUNC
        -Wno-WIDTHEXPAND
        -Wno-UNUSED         # unused signals (normal during design)
        -Wno-UNDRIVEN       # undriven signals (common in early stages)
        -Wno-PINNOCONNECT    # pin connections mismatch
        -Wno-PINCONNECTEMPTY
        -Wno-DECLFILENAME
        -Wno-IMPORTSTAR
    )
else
    # Strict mode: show almost everything
    echo "→ Running in STRICT mode — fix warnings before pushing!"
fi

echo "▶ Starting Verilator linting..."
echo "   Top module: $TOP_MODULE"
echo "   Sources:    ${RTL_SOURCES[*]}"
echo ""

# Run the linter
verilator "${VERILATOR_ARGS[@]}" "${RTL_SOURCES[@]}"

echo ""
echo "──────────────────────────────────────────────"
echo "✔ Verilator lint check PASSED!"
echo "──────────────────────────────────────────────"
echo "All good — no fatal errors or critical warnings."
echo ""
