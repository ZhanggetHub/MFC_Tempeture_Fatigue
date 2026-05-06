from __future__ import annotations

import argparse
from pathlib import Path

from mfc_life_prediction.damage_models import add_damage_scores
from mfc_life_prediction.features import build_feature_table
from mfc_life_prediction.load_cleaned import load_cleaned_spectra, load_preprocess_qc
from mfc_life_prediction.report import write_reports
from mfc_life_prediction.train import train_life_models


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract MFC temperature-damage features and train hybrid life prediction models."
    )
    parser.add_argument("--root", default=".", help="Workspace root containing outputs/stage1_preprocessed.")
    parser.add_argument("--cleaned", default=None, help="Optional path to MATLAB cleaned_spectra.csv.")
    parser.add_argument("--output", default="outputs/stage2_life_prediction", help="Output directory.")
    args = parser.parse_args()

    root = Path(args.root)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    cleaned = load_cleaned_spectra(args.cleaned, root=root)
    qc = load_preprocess_qc(root=root)
    if qc is not None:
        expected_rows_ok = bool(qc.get("row_count_ok", True).all())
        print(f"Loaded QC rows: {len(qc)}; row count check: {expected_rows_ok}")

    features = build_feature_table(cleaned)
    scored = add_damage_scores(features)

    features.to_csv(output_dir / "processed_features.csv", index=False, encoding="utf-8-sig")
    result = train_life_models(scored, output_dir)
    report_path = write_reports(result.scored, result.metrics, result.predictions, output_dir)

    print(f"Processed feature rows: {len(features)}")
    print(f"Best model: {result.model_name}")
    print(f"Report: {report_path}")


if __name__ == "__main__":
    main()
