# Скачивает и конвертирует датасеты в формат Galois (.gr/.tgr/.sgr)
# PREPARE_LJ=1 — LiveJournal для BFS/SSSP/PR
# PREPARE_TC=1 — com-Orkut для TC

set -euo pipefail

DATA_DIR="${DATA_DIR:-$HOME/graphs-data}"
GC="${GC:-$HOME/Galois/build/tools/graph-convert/graph-convert}"
URL="https://snap.stanford.edu/data/soc-LiveJournal1.txt.gz"
NAME="lj"
PREPARE_LJ="${PREPARE_LJ:-1}"
PREPARE_TC="${PREPARE_TC:-1}"

[ -x "$GC" ] || { echo "ERROR: graph-convert не найден: $GC"; exit 1; }
mkdir -p "$DATA_DIR"

if [ "$PREPARE_LJ" = "1" ]; then
    cd "$DATA_DIR"
    if [ -f "$NAME.gr" ] && [ -f "$NAME.tgr" ] && [ -f "$NAME.sgr" ]; then
        echo "LiveJournal: уже есть, пропускаем"
        ls -lh "$NAME".*
    else
        [ -f "soc-LiveJournal1.txt.gz" ] || [ -f "soc-LiveJournal1.txt" ] || [ -f "$NAME.edges" ] || \
            wget -q --show-progress "$URL" -O soc-LiveJournal1.txt.gz

        if [ ! -f "$NAME.edges" ]; then
            [ -f "soc-LiveJournal1.txt.gz" ] && gunzip soc-LiveJournal1.txt.gz
            grep -v "^#" soc-LiveJournal1.txt > "$NAME.edges"
            rm -f soc-LiveJournal1.txt
        fi

        "$GC" --edgelist2gr --edgeType=void "$NAME.edges" "$NAME.gr"
        "$GC" --gr2tgr "$NAME.gr" "$NAME.tgr"
        "$GC" --gr2sgr "$NAME.gr" "$NAME.sgr"

        # Взвешенный граф для SSSP (без весов алгоритм зависнет)
        "$GC" --gr2randomweightgr --edgeType=uint32 --maxValue=100 --minValue=1 \
            "$NAME.gr" "$NAME-w.gr"
        "$GC" --gr2tgr --edgeType=uint32 "$NAME-w.gr" "$NAME-w.tgr"

        rm -f "$NAME.edges"
        ls -lh "$DATA_DIR/$NAME".*
    fi
fi

if [ "$PREPARE_TC" = "1" ]; then
    cd "$DATA_DIR"
    TC_NAME="lj-tc"
    TC_URL="https://snap.stanford.edu/data/bigdata/communities/com-orkut.ungraph.txt.gz"
    TC_RAW="com-orkut.ungraph.txt"

    if [ -f "$TC_NAME.sgr" ]; then
        echo "TC-граф: уже есть, пропускаем"
        ls -lh "$TC_NAME".*
    else
        [ -f "$TC_RAW.gz" ] || [ -f "$TC_RAW" ] || [ -f "$TC_NAME.edges" ] || \
            wget -q --show-progress "$TC_URL" -O "$TC_RAW.gz"

        if [ ! -f "$TC_NAME.edges" ]; then
            [ -f "$TC_RAW.gz" ] && gunzip "$TC_RAW.gz"
            grep -v "^#" "$TC_RAW" > "$TC_NAME.edges"
            rm -f "$TC_RAW"
        fi

        "$GC" --edgelist2gr --edgeType=void "$TC_NAME.edges" "$TC_NAME-tmp.gr"
        "$GC" --gr2sgr "$TC_NAME-tmp.gr" "$TC_NAME-raw.sgr"
        # gr2cgr убирает self/multi-edges (для TC)
        "$GC" --gr2cgr "$TC_NAME-raw.sgr" "$TC_NAME.sgr"

        rm -f "$TC_NAME.edges" "$TC_NAME-tmp.gr" "$TC_NAME-raw.sgr"
        ls -lh "$DATA_DIR/$TC_NAME".*
    fi
fi

echo "=== Итог ($DATA_DIR) ==="
ls -lh "$DATA_DIR/" | head -20
