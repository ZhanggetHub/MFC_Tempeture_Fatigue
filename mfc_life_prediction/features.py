from __future__ import annotations

import numpy as np
import pandas as pd
from scipy import integrate, signal, stats


FREQUENCY_BANDS = {
    "b001_050": (1.0, 50.0),
    "b050_200": (50.0, 200.0),
    "b200_500": (200.0, 500.0),
    "b500_1000": (500.0, 1000.0),
    "b1000_2000": (1000.0, 2000.0),
}


CHANNEL_ALIASES = {
    "Trace Cs (F)": "Cs",
    "Trace Cp (F)": "Cp",
    "Trace |Z| (Ohm)": "Zmag",
    "Trace Rs (Ohm)": "Rs",
    "Trace Xs (Ohm)": "Xs",
    "Trace Rp (Ohm)": "Rp",
    "Trace Xp (Ohm)": "Xp",
    "Trace Ls (H)": "Ls",
    "Trace Lp (H)": "Lp",
}


def safe_channel_name(channel: str) -> str:
    return CHANNEL_ALIASES.get(channel, channel)


def build_feature_table(cleaned: pd.DataFrame) -> pd.DataFrame:
    """Create one feature row per temperature-cycle state."""

    df = cleaned.copy()
    df["short_channel"] = df["channel"].map(safe_channel_name)
    rows: list[dict[str, float | str]] = []

    group_cols = ["sample_id", "state_label", "temperature_c", "cycle_index"]
    for key, state_df in df.groupby(group_cols, dropna=False):
        row: dict[str, float | str] = {
            "sample_id": key[0],
            "state_label": key[1],
            "temperature_c": float(key[2]),
            "cycle_index": int(key[3]),
        }

        for (metric, channel), spectrum in state_df.groupby(["metric", "short_channel"]):
            prefix = f"{metric}_{channel}"
            freq = spectrum["frequency_hz"].to_numpy(float)
            value = spectrum["cleaned_value"].to_numpy(float)
            raw = spectrum["raw_value"].to_numpy(float)
            outlier = spectrum["is_outlier"].to_numpy(bool)
            row.update(_series_features(prefix, freq, value, raw, outlier))

        rows.append(row)

    features = pd.DataFrame(rows)
    features = features.sort_values(["temperature_c", "cycle_index"]).reset_index(drop=True)
    features = add_baseline_relative_features(features)
    features = add_temperature_cycle_features(features)
    return features


def _series_features(prefix: str, freq: np.ndarray, value: np.ndarray, raw: np.ndarray, outlier: np.ndarray) -> dict[str, float]:
    order = np.argsort(freq)
    freq = freq[order]
    value = value[order]
    raw = raw[order]
    outlier = outlier[order]
    finite = np.isfinite(freq) & np.isfinite(value)
    freq = freq[finite]
    value = value[finite]
    raw = raw[finite]
    outlier = outlier[finite]

    result: dict[str, float] = {}
    if len(value) == 0:
        return result

    abs_value = np.abs(value)
    diff = np.diff(value)
    abs_diff = np.abs(diff)
    norm_freq = (freq - np.nanmin(freq)) / max(np.nanmax(freq) - np.nanmin(freq), 1e-12)
    slope, intercept, r_value, _, _ = stats.linregress(norm_freq, value) if len(value) > 2 else (np.nan, np.nan, np.nan, np.nan, np.nan)

    result.update(
        {
            f"{prefix}_mean": float(np.nanmean(value)),
            f"{prefix}_std": float(np.nanstd(value)),
            f"{prefix}_median": float(np.nanmedian(value)),
            f"{prefix}_min": float(np.nanmin(value)),
            f"{prefix}_max": float(np.nanmax(value)),
            f"{prefix}_range": float(np.nanmax(value) - np.nanmin(value)),
            f"{prefix}_q05": float(np.nanquantile(value, 0.05)),
            f"{prefix}_q25": float(np.nanquantile(value, 0.25)),
            f"{prefix}_q75": float(np.nanquantile(value, 0.75)),
            f"{prefix}_q95": float(np.nanquantile(value, 0.95)),
            f"{prefix}_iqr": float(np.nanquantile(value, 0.75) - np.nanquantile(value, 0.25)),
            f"{prefix}_abs_mean": float(np.nanmean(abs_value)),
            f"{prefix}_abs_max": float(np.nanmax(abs_value)),
            f"{prefix}_rms": float(np.sqrt(np.nanmean(value**2))),
            f"{prefix}_area": float(integrate.trapezoid(value, freq)),
            f"{prefix}_abs_area": float(integrate.trapezoid(abs_value, freq)),
            f"{prefix}_slope": float(slope),
            f"{prefix}_linear_r2": float(r_value**2) if np.isfinite(r_value) else np.nan,
            f"{prefix}_roughness": float(np.nanmean(abs_diff)) if len(abs_diff) else 0.0,
            f"{prefix}_curvature": float(np.nanmean(np.abs(np.diff(value, 2)))) if len(value) > 2 else 0.0,
            f"{prefix}_outlier_rate": float(np.nanmean(outlier)) if len(outlier) else 0.0,
            f"{prefix}_cleaning_delta_mean_abs": float(np.nanmean(np.abs(value - raw))) if len(raw) else np.nan,
            f"{prefix}_low_high_ratio": _band_ratio(freq, abs_value, 1, 200, 1000, 2000),
            f"{prefix}_peak_frequency": float(freq[int(np.nanargmax(abs_value))]),
            f"{prefix}_peak_prominence": _max_peak_prominence(abs_value),
            f"{prefix}_spike_density": _spike_density(value),
            f"{prefix}_discontinuity_score": _discontinuity_score(value),
        }
    )

    for band_name, (lo, hi) in FREQUENCY_BANDS.items():
        mask = (freq >= lo) & (freq <= hi)
        if mask.any():
            band = value[mask]
            band_abs = np.abs(band)
            result[f"{prefix}_{band_name}_mean"] = float(np.nanmean(band))
            result[f"{prefix}_{band_name}_std"] = float(np.nanstd(band))
            result[f"{prefix}_{band_name}_abs_area"] = float(integrate.trapezoid(band_abs, freq[mask]))
            result[f"{prefix}_{band_name}_slope"] = _simple_slope(freq[mask], band)
        else:
            result[f"{prefix}_{band_name}_mean"] = np.nan
            result[f"{prefix}_{band_name}_std"] = np.nan
            result[f"{prefix}_{band_name}_abs_area"] = np.nan
            result[f"{prefix}_{band_name}_slope"] = np.nan

    return result


def add_baseline_relative_features(features: pd.DataFrame) -> pd.DataFrame:
    out = features.copy()
    baseline = out[out["cycle_index"] == 0]
    if baseline.empty:
        return out
    base = baseline.iloc[0]
    feature_cols = [c for c in out.columns if c not in {"sample_id", "state_label", "temperature_c", "cycle_index"}]
    additions: dict[str, pd.Series | float] = {}
    for col in feature_cols:
        if not pd.api.types.is_numeric_dtype(out[col]):
            continue
        denom = float(base[col]) if pd.notna(base[col]) else np.nan
        if np.isfinite(denom) and abs(denom) > 1e-30:
            additions[f"{col}_rel_to_baseline"] = out[col] / denom
            additions[f"{col}_delta_to_baseline"] = out[col] - denom
        else:
            additions[f"{col}_rel_to_baseline"] = np.nan
            additions[f"{col}_delta_to_baseline"] = np.nan
    if additions:
        out = pd.concat([out, pd.DataFrame(additions, index=out.index)], axis=1)
    return out.copy()


def add_temperature_cycle_features(features: pd.DataFrame) -> pd.DataFrame:
    out = features.copy()
    out["thermal_exposure_c_cycle"] = np.maximum(out["temperature_c"] - 25.0, 0.0) * out["cycle_index"].clip(lower=0)
    out["arrhenius_factor_ea_0p45ev"] = np.exp(
        -0.45 / (8.617333262e-5 * (out["temperature_c"] + 273.15))
    )
    out["normalized_temp"] = (out["temperature_c"] - 25.0) / 100.0
    return out


def _band_ratio(freq: np.ndarray, value: np.ndarray, lo1: float, hi1: float, lo2: float, hi2: float) -> float:
    m1 = (freq >= lo1) & (freq <= hi1)
    m2 = (freq >= lo2) & (freq <= hi2)
    if not m1.any() or not m2.any():
        return np.nan
    return float(np.nanmean(value[m1]) / max(np.nanmean(value[m2]), 1e-30))


def _simple_slope(freq: np.ndarray, value: np.ndarray) -> float:
    if len(value) < 2:
        return np.nan
    x = (freq - np.nanmin(freq)) / max(np.nanmax(freq) - np.nanmin(freq), 1e-12)
    return float(np.polyfit(x, value, 1)[0])


def _max_peak_prominence(value: np.ndarray) -> float:
    if len(value) < 5:
        return 0.0
    peaks, props = signal.find_peaks(value, prominence=np.nanstd(value))
    if len(peaks) == 0:
        return 0.0
    return float(np.nanmax(props.get("prominences", [0.0])))


def _spike_density(value: np.ndarray) -> float:
    if len(value) < 5:
        return 0.0
    diff = np.abs(np.diff(value))
    mad = stats.median_abs_deviation(diff, nan_policy="omit")
    threshold = np.nanmedian(diff) + 6.0 * max(mad, 1e-30)
    return float(np.nanmean(diff > threshold))


def _discontinuity_score(value: np.ndarray) -> float:
    if len(value) < 5:
        return 0.0
    diff = np.abs(np.diff(value))
    return float(np.nanquantile(diff, 0.99) / max(np.nanmedian(diff), 1e-30))
