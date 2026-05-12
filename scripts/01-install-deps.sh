# Установка зависимостей для D-Galois
set -euo pipefail

sudo apt-get update -y

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake git \
    libboost-all-dev llvm-14 llvm-14-dev libfmt-dev \
    mpich libmpich-dev libnuma-dev \
    python3 python3-pip python3-venv \
    python3-pandas python3-matplotlib python3-numpy \
    wget curl

which mpirun.openmpi || { echo "ERROR: mpirun.openmpi not found - установите libopenmpi-bin"; exit 1; }

gcc --version | head -1
cmake --version | head -1
mpirun --version | head -1
python3 -c "import pandas, matplotlib, numpy; print('python pkgs OK:', pandas.__version__, matplotlib.__version__, numpy.__version__)"
