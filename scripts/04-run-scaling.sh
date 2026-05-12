# Прогон матрицы экспериментов: алгоритм × N MPI-процессов × runs

set -euo pipefail

GRAPH="${GRAPH:-lj}"
DATA_DIR="${DATA_DIR:-$HOME/graphs-data}"
GALOIS_BUILD="${GALOIS_BUILD:-$HOME/Galois/build}"
RESULTS_DIR="${RESULTS_DIR:-$(pwd)/results}"
NS="${NS:-1 2 4 8}"
ALGOS="${ALGOS:-bfs sssp pagerank tc}"
RUNS="${RUNS:-3}"
PARTITION="${PARTITION:-oec}"
EXEC="${EXEC:-Sync}"
START_NODE="${START_NODE:-0}"
DROP_CACHES="${DROP_CACHES:-1}"
MPIRUN="${MPIRUN:-mpirun.openmpi}"
MPI_FLAGS="${MPI_FLAGS:---oversubscribe}"

DIST="$GALOIS_BUILD/lonestar/analytics/distributed"

declare -A APP=(
    [bfs]="$DIST/bfs/bfs-push-dist"
    [sssp]="$DIST/sssp/sssp-push-dist"
    [pagerank]="$DIST/pagerank/pagerank-pull-dist"
    [tc]="$DIST/triangle-counting/triangle-counting-dist"
    [cc]="$DIST/connected-components/connected-components-push-dist"
)

# Алгоритмы, требующие симметричный граф и --symmetricGraph
declare -A USES_SYMMETRIC=([tc]=1 [cc]=1)
# Алгоритмы, поддерживающие --exec
declare -A SUPPORTS_EXEC=([bfs]=1 [sssp]=1 [pagerank]=1 [tc]=0 [cc]=1)
# Алгоритмы, поддерживающие --startNode
declare -A SUPPORTS_START_NODE=([bfs]=1 [sssp]=1 [pagerank]=0 [tc]=0 [cc]=0)

mkdir -p "$RESULTS_DIR/logs"
NPROC_TOTAL="$(nproc)"

GR_FILE="$DATA_DIR/$GRAPH.gr"
TGR_FILE="$DATA_DIR/$GRAPH.tgr"
SGR_FILE="$DATA_DIR/$GRAPH.sgr"
TC_GRAPH_NAME="${TC_GRAPH:-${GRAPH}-tc}"
TC_SGR_FILE="$DATA_DIR/$TC_GRAPH_NAME.sgr"
[ -f "$TC_SGR_FILE" ] || TC_SGR_FILE="$SGR_FILE"

# SSSP требует взвешенный граф; fallback на невзвешенный
SSSP_GR_FILE="$DATA_DIR/${GRAPH}-w.gr"
SSSP_TGR_FILE="$DATA_DIR/${GRAPH}-w.tgr"
[ -f "$SSSP_GR_FILE" ] || SSSP_GR_FILE="$GR_FILE"
[ -f "$SSSP_TGR_FILE" ] || SSSP_TGR_FILE="$TGR_FILE"

[ -f "$GR_FILE" ] || { echo "ERROR: $GR_FILE not found"; exit 1; }
[ -f "$TGR_FILE" ] || echo "WARN: $TGR_FILE not found"
[ -f "$SGR_FILE" ] || echo "WARN: $SGR_FILE not found"
[ -f "$TC_SGR_FILE" ] || echo "WARN: TC-граф ($TC_SGR_FILE) not found"

echo "=== Конфигурация ==="
echo "  graph:        $GRAPH (в $DATA_DIR)"
echo "  N values:     $NS"
echo "  algorithms:   $ALGOS"
echo "  runs/algo:    $RUNS"
echo "  partition:    $PARTITION"
echo "  exec:         $EXEC"
echo "  results:      $RESULTS_DIR"
echo "  CPU cores:    $NPROC_TOTAL"
echo ""

for N in $NS; do
    # Потоков на процесс: floor(nproc/N) - 1, минимум 1
    T=$(( NPROC_TOTAL / N - 1 ))
    [ "$T" -lt 1 ] && T=1
    SUM=$(( N * T ))
    [ "$SUM" -gt "$NPROC_TOTAL" ] && \
        echo "WARN: N($N) * t($T) = $SUM > nproc($NPROC_TOTAL) — возможен oversubscribe"

    for ALGO in $ALGOS; do
        APP_BIN="${APP[$ALGO]:-}"
        [ -z "$APP_BIN" ] && { echo "ERROR: unknown algo '$ALGO'"; exit 1; }
        [ -x "$APP_BIN" ] || { echo "ERROR: $APP_BIN not found"; exit 1; }

        EFFECTIVE_TGR="$TGR_FILE"
        if [ "$ALGO" = "tc" ]; then
            INPUT="$TC_SGR_FILE"
            EFFECTIVE_TGR=""
            if [ ! -f "$INPUT" ]; then
                echo "SKIP: TC-граф отсутствует ($INPUT)"
                continue
            fi
        elif [ "$ALGO" = "sssp" ]; then
            INPUT="$SSSP_GR_FILE"
            EFFECTIVE_TGR="$SSSP_TGR_FILE"
        elif [ "${USES_SYMMETRIC[$ALGO]:-0}" = "1" ]; then
            INPUT="$SGR_FILE"
            EFFECTIVE_TGR=""
            [ -f "$INPUT" ] || { echo "ERROR: $INPUT not found"; exit 1; }
        else
            INPUT="$GR_FILE"
        fi

        STAT_CSV="$RESULTS_DIR/${ALGO}_n${N}.csv"
        LOG="$RESULTS_DIR/logs/${ALGO}_n${N}.log"

        echo "=== ${ALGO}: N=${N}, t=${T}, runs=${RUNS} ==="

        if [ "$DROP_CACHES" = "1" ] && command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
            sync && echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
        fi

        CMD=( $MPIRUN $MPI_FLAGS -n "$N"
              "$APP_BIN" "$INPUT"
              --partition="$PARTITION"
              --runs="$RUNS"
              --statFile="$STAT_CSV"
              -t "$T" )

        [ -n "$EFFECTIVE_TGR" ] && [ -f "$EFFECTIVE_TGR" ] && CMD+=( --graphTranspose="$EFFECTIVE_TGR" )
        [ "${SUPPORTS_EXEC[$ALGO]:-0}" = "1" ]       && CMD+=( --exec="$EXEC" )
        [ "${SUPPORTS_START_NODE[$ALGO]:-0}" = "1" ] && CMD+=( --startNode="$START_NODE" )
        [ "${USES_SYMMETRIC[$ALGO]:-0}" = "1" ]      && CMD+=( --symmetricGraph )

        echo "    cmd: ${CMD[*]}" | tee "$LOG"
        echo "    started: $(date -Iseconds)" | tee -a "$LOG"

        GALOIS_DO_NOT_BIND_THREADS=1 "${CMD[@]}" >> "$LOG" 2>&1 \
            && echo "    OK" | tee -a "$LOG" \
            || { echo "    FAILED (rc=$?), см. $LOG"; tail -20 "$LOG"; }
        echo "    finished: $(date -Iseconds)" | tee -a "$LOG"
        echo ""
    done
done

echo "=== Все запуски завершены ==="
ls -lh "$RESULTS_DIR"/*.csv 2>/dev/null || echo "(CSV-файлов нет — проверьте логи)"
