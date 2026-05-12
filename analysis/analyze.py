import re
import sys
from pathlib import Path

import pandas as pd
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
RESULTS_DIR = ROOT / "results"
OUT_DIR = ROOT / "analysis"
PLOTS_DIR = OUT_DIR / "plots"
PLOTS_DIR.mkdir(parents=True, exist_ok=True)

ALGO_LABELS = {
    "bfs": "BFS",
    "sssp": "SSSP",
    "pagerank": "PageRank",
    "tc": "TC",
}


def parse_galois_csv(path: Path) -> dict:
    """Извлекает времена запусков и метаданные из statFile Galois."""
    df = pd.read_csv(path, sep=r",\s*", engine="python", header=0)
    df.columns = [c.strip() for c in df.columns]

    timers = df[df["CATEGORY"].astype(str).str.match(r"^Timer_\d+$")].copy()
    timers["run"] = timers["CATEGORY"].str.extract(r"_(\d+)$").astype(int)
    timers["time_ms"] = pd.to_numeric(timers["TOTAL"], errors="coerce")

    params = df[df["STAT_TYPE"] == "PARAM"]

    def _get_param(cat):
        rows = params[params["CATEGORY"] == cat]
        return rows["TOTAL"].iloc[0] if len(rows) else None

    return {
        "runs": timers["time_ms"].dropna().tolist(),
        "hosts": int(_get_param("Hosts") or 0),
        "threads": int(_get_param("Threads") or 0),
        "input": _get_param("Input"),
    }


def main():
    if not RESULTS_DIR.is_dir():
        sys.exit(f"ERROR: {RESULTS_DIR} not found")

    rows = []
    for path in sorted(RESULTS_DIR.glob("*.csv")):
        m = re.match(r"^([a-z]+)_n(\d+)\.csv$", path.name)
        if not m:
            continue
        algo, n = m.group(1), int(m.group(2))
        try:
            parsed = parse_galois_csv(path)
        except Exception as e:
            print(f"WARN: {path.name}: {e}")
            continue
        if not parsed["runs"]:
            print(f"WARN: no Timer_X in {path.name}")
            continue
        rows.append({
            "algo": algo,
            "N": n,
            "hosts_in_csv": parsed["hosts"],
            "threads_in_csv": parsed["threads"],
            "runs_count": len(parsed["runs"]),
            "time_ms_min": min(parsed["runs"]),
            "time_ms_med": pd.Series(parsed["runs"]).median(),
            "time_ms_mean": sum(parsed["runs"]) / len(parsed["runs"]),
            "runs_raw": parsed["runs"],
        })

    if not rows:
        sys.exit("ERROR: no valid CSV files in results/")

    df = pd.DataFrame(rows).sort_values(["algo", "N"]).reset_index(drop=True)

    def add_metrics(g):
        baseline = g.loc[g["N"] == 1, "time_ms_med"]
        if not len(baseline):
            g["speedup"] = float("nan")
            g["efficiency"] = float("nan")
            return g
        t1 = baseline.iloc[0]
        g["speedup"] = t1 / g["time_ms_med"]
        g["efficiency"] = g["speedup"] / g["N"]
        return g

    df = df.groupby("algo", group_keys=False).apply(add_metrics)

    summary = df.drop(columns=["runs_raw"]).copy()
    summary["time_ms_med"] = summary["time_ms_med"].round(2)
    summary["time_ms_min"] = summary["time_ms_min"].round(2)
    summary["time_ms_mean"] = summary["time_ms_mean"].round(2)
    summary["speedup"] = summary["speedup"].round(3)
    summary["efficiency"] = summary["efficiency"].round(3)

    summary_path = OUT_DIR / "summary.csv"
    summary.to_csv(summary_path, index=False)
    print(f"=> {summary_path}")
    print(summary.to_string(index=False))
    print()

    for algo, g in df.groupby("algo"):
        label = ALGO_LABELS.get(algo, algo.upper())
        fig, axes = plt.subplots(1, 3, figsize=(15, 4.2))
        fig.suptitle(f"{label} scaling on D-Galois", fontsize=13, fontweight="bold")

        ax = axes[0]
        ax.loglog(g["N"], g["time_ms_med"], "o-", color="C0", markersize=8)
        ax.set_xlabel("N (MPI processes)")
        ax.set_ylabel("Time, ms (median)")
        ax.set_title("Execution time")
        ax.grid(True, which="both", alpha=0.3)
        ax.set_xticks(g["N"].tolist())
        ax.get_xaxis().set_major_formatter(plt.matplotlib.ticker.ScalarFormatter())

        ax = axes[1]
        ax.plot(g["N"], g["speedup"], "o-", color="C2", markersize=8, label="Actual")
        ax.plot(g["N"], g["N"], "--", color="gray", alpha=0.7, label="Ideal")
        ax.set_xlabel("N (MPI processes)")
        ax.set_ylabel("Speedup S(N) = T(1)/T(N)")
        ax.set_title("Speedup")
        ax.grid(True, alpha=0.3)
        ax.legend()
        ax.set_xticks(g["N"].tolist())

        ax = axes[2]
        ax.plot(g["N"], g["efficiency"], "o-", color="C3", markersize=8)
        ax.axhline(1.0, ls="--", color="gray", alpha=0.7, label="Ideal (= 1.0)")
        ax.set_xlabel("N (MPI processes)")
        ax.set_ylabel("Efficiency E(N) = S(N)/N")
        ax.set_title("Parallel efficiency")
        ax.grid(True, alpha=0.3)
        ax.set_ylim(0, max(1.1, g["efficiency"].max() * 1.1))
        ax.legend()
        ax.set_xticks(g["N"].tolist())

        fig.tight_layout()
        out = PLOTS_DIR / f"{algo}.png"
        fig.savefig(out, dpi=120)
        plt.close(fig)
        print(f"=> {out}")

    # Сводный график speedup всех алгоритмов
    fig, ax = plt.subplots(figsize=(8, 5.5))
    for algo, g in df.groupby("algo"):
        ax.plot(g["N"], g["speedup"], "o-", markersize=8, label=ALGO_LABELS.get(algo, algo.upper()))
    ax.plot([1, max(df["N"])], [1, max(df["N"])], "--", color="gray", alpha=0.7, label="Ideal")
    ax.set_xlabel("N (MPI processes)")
    ax.set_ylabel("Speedup S(N) = T(1)/T(N)")
    ax.set_title("D-Galois speedup across algorithms\n(LiveJournal для BFS/SSSP/PR, com-Orkut для TC)")
    ax.grid(True, alpha=0.3)
    ax.legend()
    ax.set_xticks(sorted(df["N"].unique()))
    fig.tight_layout()
    out = PLOTS_DIR / "all_speedup.png"
    fig.savefig(out, dpi=120)
    plt.close(fig)
    print(f"=> {out}")

    # Сводный график efficiency
    fig, ax = plt.subplots(figsize=(8, 5.5))
    for algo, g in df.groupby("algo"):
        ax.plot(g["N"], g["efficiency"], "o-", markersize=8, label=ALGO_LABELS.get(algo, algo.upper()))
    ax.axhline(1.0, ls="--", color="gray", alpha=0.7, label="Ideal")
    ax.set_xlabel("N (MPI processes)")
    ax.set_ylabel("Efficiency E(N)")
    ax.set_title("D-Galois parallel efficiency across algorithms")
    ax.grid(True, alpha=0.3)
    ax.legend()
    ax.set_xticks(sorted(df["N"].unique()))
    ax.set_ylim(0, max(1.1, df["efficiency"].max() * 1.1))
    fig.tight_layout()
    out = PLOTS_DIR / "all_efficiency.png"
    fig.savefig(out, dpi=120)
    plt.close(fig)
    print(f"=> {out}")


if __name__ == "__main__":
    main()
