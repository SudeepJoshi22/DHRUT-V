#!/usr/bin/env bash
set -euo pipefail

# Colors for nicer output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# -------------------------------------------------------------------
# CONFIGURATION – update these when new releases appear
# -------------------------------------------------------------------
XPACK_GCC_VER="15.2.0-1"
XPACK_GCC_TAR="xpack-riscv-none-elf-gcc-${XPACK_GCC_VER}-linux-x64.tar.gz"
XPACK_GCC_URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_GCC_VER}/${XPACK_GCC_TAR}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"
INSTALL_PREFIX="$TOOLS_DIR/toolchain"
VENV_DIR="$REPO_ROOT/venv"

GCC_DIR="$INSTALL_PREFIX/xpack-riscv-none-elf-gcc-${XPACK_GCC_VER}"

# Spike
SPIKE_SRC_DIR="$TOOLS_DIR/riscv-isa-sim"
SPIKE_DIR="$TOOLS_DIR/spike"

# Verilator – fixed: define install dir ALWAYS (even when skipping)
VERILATOR_DIR="$TOOLS_DIR/verilator"
VERILATOR_INSTALL_DIR="$TOOLS_DIR/verilator-install"   # ←←← MOVED HERE (fixes the bug)

mkdir -p "$TOOLS_DIR" "$INSTALL_PREFIX"

echo -e "${GREEN}=== DHRUT-V Setup Script (Ubuntu/Debian only) ===${NC}"
echo "This script installs:"
echo " • xPack RISC-V GCC"
echo " • Spike RISC-V ISA simulator (golden reference)"
echo " • Verilator (latest from git)"
echo " • Python venv with cocotb, pyuvm, riscof"
echo ""
echo "Install location: $INSTALL_PREFIX (repo-local)"
echo "Venv location: $VENV_DIR"
echo ""

# -------------------------------------------------------------------
# 1. System Dependencies
# -------------------------------------------------------------------
echo -e "${YELLOW}Installing required system packages...${NC}"
sudo apt update -y
sudo apt install -y \
    git wget curl python3 python3-pip python3-venv \
    autoconf automake libtool make g++ flex bison libfl-dev \
    zlib1g-dev libgoogle-perftools-dev pkg-config \
    libglib2.0-dev libpixman-1-dev ninja-build

# -------------------------------------------------------------------
# 2. xPack RISC-V GCC
# -------------------------------------------------------------------
if [ ! -d "$GCC_DIR" ]; then
    echo -e "${YELLOW}Downloading xPack RISC-V GCC...${NC}"
    wget --show-progress -O - "$XPACK_GCC_URL" | tar -xz -C "$INSTALL_PREFIX"
    echo -e "${GREEN}✓ GCC installed${NC}"
else
    echo -e "${GREEN}GCC already present${NC}"
fi
GCC_BIN="$GCC_DIR/bin"

# -------------------------------------------------------------------
# 3. Spike RISC-V ISA simulator
# -------------------------------------------------------------------
if [ ! -f "$SPIKE_DIR/bin/spike" ]; then
    echo -e "${YELLOW}Building Spike RISC-V ISA simulator (may take 2–4 min)...${NC}"
    git clone https://github.com/riscv-software-src/riscv-isa-sim.git "$SPIKE_SRC_DIR" || true
    cd "$SPIKE_SRC_DIR"
    ./configure --prefix="$SPIKE_DIR"
    make -j$(nproc)
    make install
    cd "$REPO_ROOT"
    echo -e "${GREEN}✓ Spike installed at $SPIKE_DIR/bin/spike${NC}"
else
    echo -e "${GREEN}Spike already present${NC}"
fi
SPIKE_BIN="$SPIKE_DIR/bin"

# -------------------------------------------------------------------
# 4. Verilator (now safe even when already installed)
# -------------------------------------------------------------------
if [ ! -d "$VERILATOR_INSTALL_DIR/bin" ]; then
    echo -e "${YELLOW}Building latest Verilator from git (may take 3–5 min)...${NC}"
    git clone https://github.com/verilator/verilator "$VERILATOR_DIR" || true
    cd "$VERILATOR_DIR"
    git fetch --tags
    LATEST_TAG=$(git describe --tags --abbrev=0)
    git checkout "$LATEST_TAG"
    echo "Building Verilator $LATEST_TAG..."
    autoconf
    ./configure --prefix="$VERILATOR_INSTALL_DIR"
    make -j$(nproc)
    make install
    cd "$REPO_ROOT"
    echo -e "${GREEN}✓ Verilator installed${NC}"
else
    echo -e "${GREEN}Verilator already installed → skipping build.${NC}"
fi
VERILATOR_BIN="$VERILATOR_INSTALL_DIR/bin"

# -------------------------------------------------------------------
# 5. Python venv + packages
# -------------------------------------------------------------------
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Creating Python virtual environment...${NC}"
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
echo -e "${YELLOW}Installing/updating Python packages...${NC}"
pip install --upgrade pip setuptools wheel
pip install cocotb==2.0.1 pyuvm==4.0.1 find_libpython==0.5.0 PyYAML==6.0.3
pip install git+https://github.com/riscv/riscof.git@d38859f
deactivate

# -------------------------------------------------------------------
# 6. Inject toolchain paths into venv activation
# -------------------------------------------------------------------
ACTIVATE="$VENV_DIR/bin/activate"
echo -e "${YELLOW}Updating venv activation script...${NC}"
sed -i '/# DHRUT-V TOOLCHAIN PATHS/,/echo "\[DHRUT-V\]/d' "$ACTIVATE" 2>/dev/null || true
cat << EOF >> "$ACTIVATE"
# DHRUT-V TOOLCHAIN PATHS (added by install.sh)
export PATH="$GCC_BIN:$SPIKE_BIN:$VERILATOR_BIN:\$PATH"
export RISCV="$INSTALL_PREFIX"
echo "[DHRUT-V] Environment activated: GCC + Spike + Verilator ready"
EOF

# -------------------------------------------------------------------
# Final message
# -------------------------------------------------------------------
echo -e "${GREEN}===========================================================${NC}"
echo -e "${GREEN}DHRUT-V SETUP COMPLETE!${NC}"
echo ""
echo "To activate:"
echo "  source venv/bin/activate"
echo ""
echo "Now available:"
echo "  spike --isa=rv32imac your.elf"
echo "  verilator --version"
echo "  riscv-none-elf-gcc --version"
echo ""
echo "Good luck with DHRUT-V"
echo -e "${GREEN}===========================================================${NC}"
