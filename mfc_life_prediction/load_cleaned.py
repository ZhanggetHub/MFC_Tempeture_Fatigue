from __future__ import annotations

from pathlib import Path
import re

import numpy as np
import pandas as pd


REQUIRED_COLUMNS = {
    "sample_id",
    "source_file",
    "state_label",
    "temperature_c",
    "cycle_index",
    "metric",
    "channel",
    "frequency_hz",
    "raw_value",
    "cleaned_value",
    "is_outlier",
}


def default_cleaned_path(root: str | Path = ".") -> Path:
    return Path(root) / "outputs" / "stage1_preprocessed" / "cleaned_spectra.csv"


def load_cleaned_spectra(path: str | Path | None = None, root: str | Path = ".") -> pd.DataFrame:
    """Load MATLAB-cleaned spectra and normalize column types.

    Python intentionally consumes MATLAB outputs only. If the cleaned CSV does
    not exist, run ``MFC_Stage1_Preprocess_RawSpectra.m`` first.
    """

    cleaned_path = Path(path) if path is not None else default_cleaned_path(root)
    if not cleaned_path.exists():
        raise FileNotFoundError(
            f"Cleaned spectra not found: {cleaned_path}. "
            "Run MFC_Stage1_Preprocess_RawSpectra.m first."
        )

    df = pd.read_csv(cleaned_path, encoding="utf-8-sig")
    missing = REQUIRED_COLUMNS.difference(df.columns)
    if missing:
        raise ValueError(f"Cleaned spectra is missing required columns: {sorted(missing)}")

    numeric_cols = ["temperature_c", "cycle_index", "frequency_hz", "raw_value", "cleaned_value"]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df["is_outlier"] = df["is_outlier"].astype(str).str.lower().isin(["1", "true", "yes"])

    df["metric"] = df["metric"].astype(str)
    df["channel"] = df["channel"].astype(str)
    df["state_label"] = df["state_label"].astype(str)
    df["sample_id"] = df["sample_id"].astype(str)

    # Safety repair for MATLAB export variants.
    parsed = df["source_file"].astype(str).apply(parse_state_from_filename)
    missing_temp = df["temperature_c"].isna()
    if missing_temp.any():
        df.loc[missing_temp, "temperature_c"] = parsed.loc[missing_temp].map(lambda x: x[0]).astype(float)
    missing_cycle = df["cycle_index"].isna()
    if missing_cycle.any():
        df.loc[missing_cycle, "cycle_index"] = parsed.loc[missing_cycle].map(lambda x: x[1]).astype(float)

    return df.sort_values(
        ["metric", "temperature_c", "cycle_index", "channel", "frequency_hz"]
    ).reset_index(drop=True)


def load_preprocess_qc(root: str | Path = ".") -> pd.DataFrame | None:
    path = Path(root) / "outputs" / "stage1_preprocessed" / "preprocess_qc.csv"
    if not path.exists():
        return None
    return pd.read_csv(path, encoding="utf-8-sig")


def parse_state_from_filename(name: str) -> tuple[float, int, str]:
    match = re.search(r"(\d+)度第(\d+)次退化", name)
    if match:
        temp = float(match.group(1))
        cycle = int(match.group(2))
        return temp, cycle, f"{int(temp)}C_cycle_{cycle}"
    if "基线" in name:
        return 25.0, 0, "baseline"
    return np.nan, -1, "unknown"
