# MFC Temperature Fatigue Life Prediction

Repository alias: `MFC_Tempeture_Fatigue`

This repository contains MATLAB and Python code for preprocessing and modeling
temperature-induced degradation of D31 Macro Fiber Composite (MFC) sensor
performance.

## Workflow

1. Run MATLAB preprocessing on raw WaveForms CSV exports:

   ```matlab
   MFC_Stage1_Preprocess_RawSpectra
   ```

   This creates cleaned spectra, QC tables, and optional QC plots under
   `outputs/stage1_preprocessed/`.

2. Run Python feature extraction, physics-constrained damage scoring, and life
   prediction:

   ```powershell
   python run_stage2_feature_and_life_prediction.py
   ```

   This creates `processed_features.csv`, `health_index.csv`,
   `model_metrics.csv`, `life_predictions.csv`, and report figures under
   `outputs/stage2_life_prediction/`.

## Repository Boundary

The Git project tracks source code and documentation only. Raw experimental
folders, WaveForms exports, COMSOL models, MATLAB/Python caches, and generated
outputs are intentionally ignored by `.gitignore`.

## Main Files

- `MFC_Preprocess_Config.m`: MATLAB preprocessing configuration.
- `MFC_Stage1_Preprocess_RawSpectra.m`: raw CSV cleaning and QC export.
- `MFC_QC_Plots.m`: MATLAB before/after cleaning plots.
- `mfc_life_prediction/`: Python package for features, damage models, training,
  and reporting.
- `run_stage2_feature_and_life_prediction.py`: Python stage-2 entry point.

