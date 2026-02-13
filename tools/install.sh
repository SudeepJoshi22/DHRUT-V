#!/usr/bin/env bash
set -euo pipefail  # Strict mode: exit on error, undefined vars, pipe failures

echo "=== RISC-V + Verilator + pyUVM Setup Script ==="
echo "This script installs:"
echo "  - RISC-V GNU Toolchain (RV32IMAC / RV64IMAC support)"
echo "  - Spike (RISC-V ISA Simulator)"
echo "  - Verilator (Verilog/SystemVerilog Simulator)"
echo "  - Python virtual environment with cocotb, pyuvm, find_libpython, PyYAML"
echo "  - RISCOF (RISC-V Architectural Test Framework)"
echo "Target: Ubuntu/Debian-based systems"
echo "Install location: /opt/riscv (toolchain & spike), system-wide Verilator"
echo "Python env: ~/riscv_pyenv"
echo ""

# Check for root/sudo
if [[ $EUID -eq 0 ]]; then
   echo "Do not run as root — sudo will be used when needed"
   exit 1
fi

# Update system and install build dependencies
echo "Installing system dependencies..."
sudo apt update
sudo apt install -y \
    autoconf automake autotools-dev curl python3 python3-pip python3-venv libmpc-dev \
    libmpfr-dev libgmp-dev gawk build-essential bison flex texinfo \
    gperf libtool patchutils bc zlib1g-dev libexpat-dev ninja-build \
    git pkg-config libglib2.0-dev libpixman-1-dev libssl-dev

# Create install directory
INSTALL_PREFIX="/opt/riscv"
sudo mkdir -p "$INSTALL_PREFIX"
sudo chown "$USER":"$USER" "$INSTALL_PREFIX"

# ===================================================================
# 1. RISC-V GNU Toolchain (riscv-gnu-toolchain)
# ===================================================================
echo ""
echo "Installing RISC-V GNU Toolchain to $INSTALL_PREFIX..."

if [ ! -d "riscv-gnu-toolchain" ]; then
    git clone https://github.com/riscv/riscv-gnu-toolchain.git
fi

cd riscv-gnu-toolchain
git pull
git submodule update --init --recursive

./configure --prefix="$INSTALL_PREFIX" --enable-multilib
make -j"$(nproc)"
sudo make install
cd ..

# ===================================================================
# 2. Spike (riscv-isa-sim)
# ===================================================================
echo ""
echo "Installing Spike to $INSTALL_PREFIX..."

if [ ! -d "riscv-isa-sim" ]; then
    git clone https://github.com/riscv-software-src/riscv-isa-sim.git
fi

cd riscv-isa-sim
git pull
git submodule update --init --recursive

mkdir -p build
cd build
../configure --prefix="$INSTALL_PREFIX" --enable-commitlog
make -j"$(nproc)"
sudo make install
cd ../..

# ===================================================================
# 3. Verilator
# ===================================================================
echo ""
echo "Installing Verilator (system-wide)..."

if [ ! -d "verilator" ]; then
    git clone https://github.com/verilator/verilator.git
fi

cd verilator
git pull
git checkout stable  # stable branch

autoconf
./configure
make -j"$(nproc)"
sudo make install
cd ..

# ===================================================================
# 4. Python Virtual Environment + cocotb + pyuvm + extras + RISCOF
# ===================================================================
echo ""
echo "Creating Python virtual environment at ~/riscv_pyenv..."

python3 -m venv ~/riscv_pyenv
# shellcheck disable=SC1090
source ~/riscv_pyenv/bin/activate

echo "Upgrading pip and installing packages..."
pip install --upgrade pip

# Existing packages
pip install cocotb==2.0.1 pyuvm==4.0.1 find_libpython==0.5.0 PyYAML==6.0.3

# RISCOF (preferred install per docs: latest from upstream git)
pip install git+https://github.com/riscv/riscof.git@d38859f

echo ""
echo "Verifying RISCOF installation..."
riscof --help >/dev/null

deactivate

# ===================================================================
# Add to PATH (permanent)
# ===================================================================
echo ""
echo "Adding $INSTALL_PREFIX/bin to PATH..."
echo "export PATH=\"$INSTALL_PREFIX/bin:\$PATH\"" >> ~/.bashrc
echo "export RISCV=\"$INSTALL_PREFIX\"" >> ~/.bashrc

# Add virtual env activation note
echo ""
echo "To activate Python environment with cocotb/pyuvm/riscof:"
echo "  source ~/riscv_pyenv/bin/activate"

echo ""
echo "=== Installation Complete! ==="
echo "Toolchain: $INSTALL_PREFIX/bin/riscv64-unknown-elf-gcc (etc.)"
echo "Spike:     $INSTALL_PREFIX/bin/spike"
echo "Verilator: verilator (system-wide)"
echo "Python env: ~/riscv_pyenv (with cocotb==2.0.1, pyuvm==4.0.1, riscof installed)"
echo ""
echo "Reload your shell or run: source ~/.bashrc"
echo "Verify:"
echo "  riscv64-unknown-elf-gcc --version"
echo "  spike --version"
echo "  verilator --version"
echo "  source ~/riscv_pyenv/bin/activate && riscof --version && pip list"
