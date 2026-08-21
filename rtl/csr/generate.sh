#!/usr/bin/env bash
# rtl/csr/generate.sh - Regenerate RTL (and, optionally, docs) from csr_regfile.rdl
#
# Usage:
#   ./rtl/csr/generate.sh          # regenerate rtl/csr/generated/ (tracked in git)
#   ./rtl/csr/generate.sh docs     # also regenerate rtl/csr/html_ref/ (gitignored, local-only)
#
# See rtl/csr/README.md for what this directory is and how it fits into the build.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
PEAKRDL="$REPO_ROOT/venv/bin/peakrdl"
RDL_FILE="$SCRIPT_DIR/csr_regfile.rdl"

if [ ! -x "$PEAKRDL" ]; then
    echo "peakrdl not found at $PEAKRDL - installing into venv/ ..."
    "$REPO_ROOT/venv/bin/pip" install peakrdl peakrdl-regblock
fi

echo "▶ Generating RTL from $RDL_FILE"
rm -rf "$SCRIPT_DIR/generated"
"$PEAKRDL" regblock "$RDL_FILE" -o "$SCRIPT_DIR/generated" --cpuif passthrough --module-name csr_regfile_gen --default-reset arst_n
echo "✔ RTL written to $SCRIPT_DIR/generated/"

if [ "${1:-}" = "docs" ]; then
    echo "▶ Generating HTML docs from $RDL_FILE"
    rm -rf "$SCRIPT_DIR/html_ref"
    "$PEAKRDL" html "$RDL_FILE" -o "$SCRIPT_DIR/html_ref" --title "DHRUT-V M-mode CSR Block"
    echo "✔ Docs written to $SCRIPT_DIR/html_ref/index.html (gitignored, local-only)"
fi
