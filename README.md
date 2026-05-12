# Распределённая обработка графов на D-Galois

**оценка масштабируемости распределённого графового
движка [D-Galois](https://github.com/IntelligentSoftwareSystems/Galois)** по числу узлов (MPI-процессов) на одной
машине.

> Запуская `mpirun -n N` локально, мы измеряем, как ускоряется обработка
> графа при увеличении N (MPI-процессов).

## Результаты

Полный отчёт с интерпретацией — [`report.md`](docs/report.md). Кратко:

| Алгоритм | T(1)   | T(4)   | Speedup max       | Эффективность max |
|----------|--------|--------|-------------------|-------------------|
| BFS      | 1.35 s | 0.89 s | **1.51× при N=4** | 0.42              |
| SSSP     | 6.7 s  | 3.06 s | **2.18× при N=4** | 0.60              |
| PageRank | 88 s   | 27 s   | **3.25× при N=4** | 0.81              |
| TC       | 358 s  | 107 s  | **3.35× при N=4** | 0.94 при N=2      |

Графики — в [`analysis/plots/`](analysis/plots/), сводная таблица — [`analysis/summary.csv`](analysis/summary.csv).

## Как запускать

### Требования

| Что             | Требование                                                      |
|-----------------|-----------------------------------------------------------------|
| ОС              | Linux (Ubuntu 22.04+ рекомендуется) или WSL2 я только под Linux |
| RAM             | 8 GiB                                                           |
| Свободное место | ~5 GB (под графы и тд)                                          |
| CPU             | ≥ 4 логических ядер                                             |

Подробности окружения в котором запускался эксперимент — в [`environment.md`](docs/environment.md).

```bash
git clone https://github.com/Lesh79/graphs.git && cd graphs
bash scripts/01-install-deps.sh        # apt-зависимости
bash scripts/02-build-galois.sh        # клон + сборка D-Galois (15-30 минут)
bash scripts/03-prepare-data.sh        # LiveJournal -> .gr/.tgr/.sgr
bash scripts/04-run-scaling.sh         # основной прогон (16 запусков, ~1 час)
python3 analysis/analyze.py            # сводная таблица + графики


bash scripts/05-smoke-test.sh          # smoke-проверка всей цепочки
```

После прохождения всех шагов сводная таблица окажется в `analysis/summary.csv`, графики — в `analysis/plots/`.

## Алгоритмы эксперимента

- **BFS** — Breadth-First Search (`bfs-push-dist`)
- **SSSP** — Single-Source Shortest Path (`sssp-push-dist`)
- **PR** — PageRank (`pagerank-pull-dist`)
- **TC** — Triangle Counting (`triangle-counting-dist`)

!!!!!! для TC используется **отдельный граф** (com-Orkut, файл `lj-tc.sgr`), т.к. D-Galois TC требует
неориентированный граф
без self/multi-edges. Скачается автоматически в `scripts/03-prepare-data.sh`.

Детали — в [`experiments/design.md`](docs/design.md).

## Датасеты

| Файл        | Граф                               | \|V\|     | \|E\|       | Размер | Используется для  |
|-------------|------------------------------------|-----------|-------------|--------|-------------------|
| `lj.gr`     | LiveJournal (направленный)         | 4 847 571 | 68 993 773  | 301 MB | BFS, PageRank     |
| `lj.tgr`    | LiveJournal (транспонированный)    | 4 847 571 | 68 993 773  | 301 MB | PageRank pull     |
| `lj-w.gr`   | LiveJournal + веса uint32 [1..100] | 4 847 571 | 68 993 773  | 564 MB | SSSP              |
| `lj-w.tgr`  | тоже, транспонированный            | —         | —           | 564 MB | SSSP pull         |
| `lj-tc.sgr` | симметричный, очищен от весов      | 3 072 627 | 117 185 083 | 918 MB | Triangle Counting |

**LiveJournal** выбран как основной граф: реалистичное степенное распределение (69M рёбер),
качал со [SNAP](https://snap.stanford.edu/data/soc-LiveJournal1.html).

**com-Orkut** используется только для TC — D-Galois TC требует строго симметричный граф без self/multi-edges, прямая
симметризация LiveJournal искажает его свойства.

Для smoke-теста используется `rmat15` (~32K узлов), поставляемый вместе с Galois.
