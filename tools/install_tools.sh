echo "Initializing..."
export PROJ := "$PWD"
#sudo apt update
sudo apt install -y iverilog gtkwave
sudo apt install libmpc3 device-tree-compiler

echo "Entering Root ..."

echo "Downloading Pre-build RISCV-GCC and SPIKE..";
#wget 'https://matthieu-moy.fr/spip/IMG/xz/riscv.tar.xz' -O /tmp/riscv.tar.xz

cd /opt/
#sudo tar -xJvf /tmp/riscv.tar.xz
cd
echo "Editing the .bashrc file"
echo 'PATH=/opt/bin:$PATH' >> .bashrc
cd $PROJ
echo "Entering the Project Directry"

