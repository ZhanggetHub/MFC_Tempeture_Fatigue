from __future__ import annotations

import numpy as np
import pandas as pd


def add_damage_scores(features: pd.DataFrame) -> pd.DataFrame:
    """Compute physically motivated proxy damage scores in [0, 1]."""

    out = features.copy()

    crack_inputs = [
        _col(out, "Impedance_Rs_mean_rel_to_baseline", transform="increase"),
        _col(out, "Impedance_Rp_mean_rel_to_baseline", transform="increase"),
        _col(out, "Impedance_Zmag_discontinuity_score_rel_to_baseline", transform="increase"),
        _col(out, "Impedance_Zmag_spike_density_delta_to_baseline", transform="increase"),
    ]
    breakdown_inputs = [
        _col(out, "Impedance_Rp_mean_rel_to_baseline", transform="decrease"),
        _col(out, "Impedance_Zmag_mean_rel_to_baseline", transform="decrease"),
        _col(out, "Capacitance_Cs_discontinuity_score_rel_to_baseline", transform="increase"),
        _col(out, "Capacitance_Cp_spike_density_delta_to_baseline", transform="increase"),
    ]
    depol_inputs = [
        _col(out, "Capacitance_Cs_mean_rel_to_baseline", transform="distance_from_1"),
        _col(out, "Capacitance_Cp_mean_rel_to_baseline", transform="distance_from_1"),
        _col(out, "Impedance_Xs_abs_mean_rel_to_baseline", transform="distance_from_1"),
    ]

    thermal = _thermal_damage(out["temperature_c"].to_numpy(float), out["cycle_index"].to_numpy(float))
    crack = _combine(crack_inputs)
    breakdown = _combine(breakdown_inputs)
    depol = np.clip(0.65 * _combine(depol_inputs) + 0.35 * thermal, 0.0, 1.0)

    out["D_thermal"] = thermal
    out["D_crack"] = crack
    out["D_breakdown"] = breakdown
    out["D_depolarization"] = depol
    out["D_total"] = np.clip(0.25 * thermal + 0.25 * crack + 0.20 * breakdown + 0.30 * depol, 0.0, 1.0)
    out["health_index"] = np.clip(1.0 - out["D_total"], 0.0, 1.0)
    out["failure_probability"] = 1.0 / (1.0 + np.exp(-12.0 * (out["D_total"] - 0.65)))
    out["failure_label"] = (out["D_total"] >= 0.65).astype(int)

    modes = out[["D_thermal", "D_crack", "D_breakdown", "D_depolarization"]].idxmax(axis=1)
    out["dominant_damage_mode"] = modes.str.replace("D_", "", regex=False)
    return out


def _thermal_damage(temp_c: np.ndarray, cycle: np.ndarray) -> np.ndarray:
    temp_excess = np.clip((temp_c - 25.0) / 95.0, 0.0, None)
    cycle_factor = np.clip(cycle / 3.0, 0.0, None)
    arr = np.exp(-0.45 / (8.617333262e-5 * (temp_c + 273.15)))
    arr_norm = arr / max(np.nanmax(arr), 1e-30)
    return np.clip(0.45 * temp_excess + 0.35 * cycle_factor + 0.20 * arr_norm * cycle_factor, 0.0, 1.0)


def _col(df: pd.DataFrame, name: str, transform: str) -> np.ndarray:
    if name not in df.columns:
        return np.zeros(len(df), dtype=float)
    x = pd.to_numeric(df[name], errors="coerce").to_numpy(float)
    if transform == "increase":
        y = np.maximum(x - 1.0, 0.0)
    elif transform == "decrease":
        y = np.maximum(1.0 - x, 0.0)
    elif transform == "distance_from_1":
        y = np.abs(x - 1.0)
    else:
        y = x
    return _robust_unit(y)


def _robust_unit(x: np.ndarray) -> np.ndarray:
    x = np.nan_to_num(x, nan=0.0, posinf=0.0, neginf=0.0)
    lo = np.nanquantile(x, 0.05)
    hi = np.nanquantile(x, 0.95)
    if not np.isfinite(hi - lo) or hi <= lo:
        hi = np.nanmax(x)
        lo = np.nanmin(x)
    if hi <= lo:
        return np.zeros_like(x)
    return np.clip((x - lo) / (hi - lo), 0.0, 1.0)


def _combine(parts: list[np.ndarray]) -> np.ndarray:
    if not parts:
        return np.array([])
    stack = np.vstack(parts)
    return np.clip(np.nanmean(stack, axis=0), 0.0, 1.0)
