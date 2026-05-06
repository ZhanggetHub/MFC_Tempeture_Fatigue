from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def write_reports(scored: pd.DataFrame, metrics: pd.DataFrame, predictions: pd.DataFrame, output_dir: str | Path) -> Path:
    output_dir = Path(output_dir)
    fig_dir = output_dir / "figures"
    fig_dir.mkdir(parents=True, exist_ok=True)

    _plot_health(scored, fig_dir / "health_index_by_temperature.png")
    _plot_damage(scored, fig_dir / "damage_components.png")
    _plot_rul(predictions, fig_dir / "estimated_rul_cycles.png")

    report_path = output_dir / "life_prediction_report.md"
    best = metrics.iloc[0].to_dict() if not metrics.empty else {}
    lines = [
        "# MFC temperature fatigue life prediction report",
        "",
        "## Best model",
        f"- Model: {best.get('model', 'n/a')}",
        f"- MAE: {best.get('mae', float('nan')):.6f}",
        f"- RMSE: {best.get('rmse', float('nan')):.6f}",
        f"- R2: {best.get('r2', float('nan')):.6f}",
        f"- Failure accuracy: {best.get('failure_accuracy', float('nan')):.6f}",
        "",
        "## Output files",
        "- processed_features.csv",
        "- health_index.csv",
        "- model_metrics.csv",
        "- life_predictions.csv",
        "- figures/health_index_by_temperature.png",
        "- figures/damage_components.png",
        "- figures/estimated_rul_cycles.png",
        "",
        "## Notes",
        "- Failure labels are hybrid proxy labels derived from performance degradation plus physical damage constraints.",
        "- Electrode crack, breakdown, and depolarization scores are impedance/capacitance/inductance spectrum proxy variables.",
    ]
    report_path.write_text("\n".join(lines), encoding="utf-8")
    return report_path


def _plot_health(scored: pd.DataFrame, path: Path) -> None:
    fig, ax = plt.subplots(figsize=(9, 5), dpi=160)
    for temp, g in scored.sort_values("cycle_index").groupby("temperature_c"):
        ax.plot(g["cycle_index"], g["health_index"], marker="o", label=f"{temp:g} C")
    ax.set_xlabel("Cycle index")
    ax.set_ylabel("Health index")
    ax.set_ylim(0, 1.05)
    ax.grid(True, alpha=0.3)
    ax.legend(ncol=2, fontsize=8)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def _plot_damage(scored: pd.DataFrame, path: Path) -> None:
    cols = ["D_thermal", "D_crack", "D_breakdown", "D_depolarization", "D_total"]
    fig, ax = plt.subplots(figsize=(10, 5), dpi=160)
    x = range(len(scored))
    labels = [f"{r.temperature_c:g}C-{int(r.cycle_index)}" for r in scored.itertuples()]
    for col in cols:
        ax.plot(x, scored[col], marker=".", label=col)
    ax.set_xticks(list(x))
    ax.set_xticklabels(labels, rotation=60, ha="right", fontsize=7)
    ax.set_ylabel("Damage score")
    ax.set_ylim(0, 1.05)
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def _plot_rul(predictions: pd.DataFrame, path: Path) -> None:
    fig, ax = plt.subplots(figsize=(8, 4.8), dpi=160)
    ax.bar(predictions["temperature_c"].astype(str), predictions["estimated_rul_cycles"])
    ax.set_xlabel("Temperature (C)")
    ax.set_ylabel("Estimated RUL (cycles)")
    ax.grid(True, axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
