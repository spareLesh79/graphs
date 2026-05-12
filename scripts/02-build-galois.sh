# Клонирование и сборка D-Galois
# Использование: JOBS=4 bash scripts/02-build-galois.sh

set -euo pipefail

JOBS="${JOBS:-2}"
GALOIS_DIR="${GALOIS_DIR:-$HOME/Galois}"
GALOIS_BRANCH="${GALOIS_BRANCH:-master}"

if [ ! -d "$GALOIS_DIR/.git" ]; then
    if [ "$GALOIS_BRANCH" = "master" ]; then
        git clone --depth 1 https://github.com/IntelligentSoftwareSystems/Galois.git "$GALOIS_DIR"
    else
        git clone --depth 1 -b "$GALOIS_BRANCH" \
            https://github.com/IntelligentSoftwareSystems/Galois.git "$GALOIS_DIR"
    fi
else
    echo "уже склонен"
fi

cd "$GALOIS_DIR"
git submodule update --init --recursive

# Cj,bhftv
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DGALOIS_ENABLE_DIST=1
make -j"${JOBS}" -C lonestar/analytics/distributed
make -j"${JOBS}" -C tools/graph-convert

ls "$GALOIS_DIR/build/lonestar/analytics/distributed/bfs/bfs-push-dist"
"$GALOIS_DIR/build/lonestar/analytics/distributed/bfs/bfs-push-dist" --help > /dev/null
echo "OK: bfs-push-dist собран"
ls "$GALOIS_DIR/build/tools/graph-convert/graph-convert"
echo "OK: graph-convert собран"
