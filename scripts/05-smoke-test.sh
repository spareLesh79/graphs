# Smoke-тест: проверяет всю цепочку на rmat15 (маленький граф)

set -euo pipefail

GALOIS_BUILD="${GALOIS_BUILD:-$HOME/Galois/build}"
SMOKE_DATA="${SMOKE_DATA:-$HOME/graphs-data/smoke}"
INPUTS_DIR="$GALOIS_BUILD/inputs"
MPIRUN="${MPIRUN:-mpirun.openmpi}"

# Качаем
if [ ! -f "$INPUTS_DIR/scalefree/rmat15.gr" ]; then
    [ -s "$INPUTS_DIR/lonestar-cpu-inputs.tar.gz" ] || \
        wget -q --show-progress \
            https://iss.oden.utexas.edu/projects/galois/downloads/small_inputs_for_lonestar_test.tar.gz \
            -O "$INPUTS_DIR/lonestar-cpu-inputs.tar.gz"
    (cd "$INPUTS_DIR" && tar xzf lonestar-cpu-inputs.tar.gz)
fi

mkdir -p "$SMOKE_DATA"
cp -u "$INPUTS_DIR/scalefree/rmat15.gr"            "$SMOKE_DATA/rmat15.gr"
cp -u "$INPUTS_DIR/scalefree/transpose/rmat15.tgr" "$SMOKE_DATA/rmat15.tgr"
cp -u "$INPUTS_DIR/scalefree/symmetric/rmat15.sgr" "$SMOKE_DATA/rmat15.sgr"
ls -lh "$SMOKE_DATA/"rmat15.*

# запуск BFS для быстрой проверки
GALOIS_DO_NOT_BIND_THREADS=1 "$MPIRUN" --oversubscribe -n 2 \
    "$GALOIS_BUILD/lonestar/analytics/distributed/bfs/bfs-push-dist" \
    "$SMOKE_DATA/rmat15.gr" \
    --graphTranspose="$SMOKE_DATA/rmat15.tgr" \
    -t 2 --partition=oec --runs=1 --exec=Sync \
    | grep -E "Hosts,|Number of nodes|Timer|FATAL" || true

# Прогон через основной скрипт
SMOKE_RESULTS="$(pwd)/results_smoke"
rm -rf "$SMOKE_RESULTS"

GRAPH=rmat15 \
DATA_DIR="$SMOKE_DATA" \
NS="1 2" \
ALGOS="bfs sssp pagerank" \
RUNS=1 \
DROP_CACHES=0 \
RESULTS_DIR="$SMOKE_RESULTS" \
bash "$(dirname "$0")/04-run-scaling.sh"

ls -lh "$SMOKE_RESULTS"/*.csv 2>/dev/null
echo "OK: smoke-тест пройден. Удалите $SMOKE_RESULTS перед основным прогоном."
