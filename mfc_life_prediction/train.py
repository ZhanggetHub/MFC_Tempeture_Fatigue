from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.optimize import curve_fit
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import GradientBoostingRegressor, RandomForestRegressor
from sklearn.impute import SimpleImputer
from sklearn.metrics import accuracy_score, mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import LeaveOneGroupOut, cross_val_predict
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVR


NON_FEATURE_COLUMNS = {
    "sample_id",
    "state_label",
    "dominant_damage_mode",
}


@dataclass
class TrainingResult:
    scored: pd.DataFrame
    metrics: pd.DataFrame
    predictions: pd.DataFrame
    model_name: str


def train_life_models(scored: pd.DataFrame, output_dir: str | Path) -> TrainingResult:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    data = scored.copy()
    feature_cols = [
        c
        for c in data.columns
        if c not in NON_FEATURE_COLUMNS
        and c not in {"health_index", "D_total", "failure_probability", "failure_label"}
        and pd.api.types.is_numeric_dtype(data[c])
    ]
    feature_cols = [c for c in feature_cols if not data[c].isna().all()]
    if not feature_cols:
        raise ValueError("No usable numeric feature columns were found after dropping all-NaN features.")
    X = data[feature_cols]
    y = data["health_index"].astype(float)
    groups = data["temperature_c"].astype(float)

    models = {
        "random_forest": RandomForestRegressor(n_estimators=300, random_state=42, min_samples_leaf=2),
        "gradient_boosting": GradientBoostingRegressor(random_state=42),
        "svr_rbf": Pipeline([("scale", StandardScaler()), ("svr", SVR(C=10.0, gamma="scale"))]),
    }

    metric_rows = []
    cv_predictions: dict[str, np.ndarray] = {}
    unique_groups = pd.Series(groups).dropna().unique()
    if len(unique_groups) >= 2:
        logo = LeaveOneGroupOut()
        splits = list(logo.split(X, y, groups=groups))
    else:
        splits = []

    for name, model in models.items():
        pipe = Pipeline([("impute", SimpleImputer(strategy="median")), ("model", model)])
        if len(splits) >= 2 and len(data) > 4:
            pred = cross_val_predict(pipe, X, y, cv=splits)
        else:
            pipe.fit(X, y)
            pred = pipe.predict(X)
        pred = np.clip(pred, 0.0, 1.0)
        cv_predictions[name] = pred
        metric_rows.append(_regression_metrics(name, y, pred, data["failure_label"]))

    metrics = pd.DataFrame(metric_rows).sort_values(["rmse", "mae"]).reset_index(drop=True)
    best_name = str(metrics.iloc[0]["model"])
    best_model = Pipeline([("impute", SimpleImputer(strategy="median")), ("model", models[best_name])])
    best_model.fit(X, y)

    final_pred = np.clip(best_model.predict(X), 0.0, 1.0)
    data["predicted_health_index"] = final_pred
    data["predicted_D_total"] = np.clip(1.0 - final_pred, 0.0, 1.0)
    data["predicted_failure_probability"] = 1.0 / (1.0 + np.exp(-12.0 * (data["predicted_D_total"] - 0.65)))

    life_curve = fit_life_curve(data)
    data = data.merge(life_curve, on=["temperature_c", "cycle_index"], how="left")
    predictions = project_future_life(data, best_model, feature_cols)

    data.to_csv(output_dir / "health_index.csv", index=False, encoding="utf-8-sig")
    metrics.to_csv(output_dir / "model_metrics.csv", index=False, encoding="utf-8-sig")
    predictions.to_csv(output_dir / "life_predictions.csv", index=False, encoding="utf-8-sig")
    (output_dir / "model_summary.json").write_text(
        json.dumps({"best_model": best_name, "feature_count": len(feature_cols)}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    return TrainingResult(scored=data, metrics=metrics, predictions=predictions, model_name=best_name)


def _regression_metrics(name: str, y_true: pd.Series, y_pred: np.ndarray, failure_label: pd.Series) -> dict[str, float | str]:
    predicted_failure = (1.0 - y_pred >= 0.65).astype(int)
    return {
        "model": name,
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "r2": float(r2_score(y_true, y_pred)) if len(np.unique(y_true)) > 1 else np.nan,
        "failure_accuracy": float(accuracy_score(failure_label, predicted_failure)),
    }


def fit_life_curve(data: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for temp, g in data[data["cycle_index"] > 0].groupby("temperature_c"):
        x = g["cycle_index"].to_numpy(float)
        damage = g["D_total"].to_numpy(float)
        if len(g) < 2:
            continue
        try:
            popt, _ = curve_fit(_weibull_damage, x, damage, bounds=([0.01, 0.1], [10.0, 10.0]), maxfev=10000)
            fitted = _weibull_damage(x, *popt)
            eol_cycle = _solve_eol_cycle(popt, threshold=0.65)
        except Exception:
            coef = np.polyfit(x, damage, 1)
            fitted = np.polyval(coef, x)
            eol_cycle = (0.65 - coef[1]) / max(coef[0], 1e-12)
        for cycle, fit in zip(x, fitted):
            rows.append({"temperature_c": temp, "cycle_index": int(cycle), "fitted_damage_path": float(np.clip(fit, 0, 1)), "estimated_eol_cycle_at_temp": float(eol_cycle)})
    return pd.DataFrame(rows)


def project_future_life(data: pd.DataFrame, model: Pipeline, feature_cols: list[str]) -> pd.DataFrame:
    latest = data.sort_values(["temperature_c", "cycle_index"]).groupby("temperature_c").tail(1)
    rows = []
    for _, row in latest.iterrows():
        eol = row.get("estimated_eol_cycle_at_temp", np.nan)
        current = row["cycle_index"]
        rul = max(float(eol - current), 0.0) if np.isfinite(eol) else np.nan
        rows.append(
            {
                "temperature_c": row["temperature_c"],
                "current_cycle": current,
                "current_health_index": row["health_index"],
                "predicted_health_index": row["predicted_health_index"],
                "estimated_eol_cycle": eol,
                "estimated_rul_cycles": rul,
                "dominant_damage_mode": row["dominant_damage_mode"],
                "failure_probability": row["predicted_failure_probability"],
            }
        )
    return pd.DataFrame(rows).sort_values("temperature_c")


def _weibull_damage(cycle: np.ndarray, eta: float, beta: float) -> np.ndarray:
    return 1.0 - np.exp(-((cycle / eta) ** beta))


def _solve_eol_cycle(params: np.ndarray, threshold: float) -> float:
    eta, beta = params
    threshold = np.clip(threshold, 1e-6, 0.999999)
    return float(eta * (-np.log(1.0 - threshold)) ** (1.0 / beta))
