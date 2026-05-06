function cfg = MFC_Preprocess_Config()
% Configuration for MFC raw impedance-spectrum preprocessing.
%
% MATLAB is the only raw CSV preprocessing entry point in this workflow.
% Python should consume the cleaned CSV/MAT outputs generated here.

cfg.targetFolder = '0 45 0 45 0 编织纹复材D31 MFC-温度导致传感性能退化试验';
cfg.outputFolder = fullfile(pwd, 'outputs', 'stage1_preprocessed');
cfg.figureFolder = fullfile(cfg.outputFolder, 'qc_plots');

cfg.allowedSuffixes = {'Capacitance', 'Impedance', 'Inductance'};
cfg.headerLines = 30;
cfg.expectedRowsPerFile = 2000;

% Filtering parameters. Windows are odd sample counts.
cfg.hampelWindow = 11;
cfg.hampelSigma = 3.0;
cfg.medianWindow = 5;
cfg.sgWindow = 21;
cfg.sgOrder = 3;

% Robust local abnormal-point detection.
cfg.localWindow = 21;
cfg.localMadSigma = 6.0;
cfg.globalMadSigma = 12.0;

% Conservative physical sanity limits. They are intentionally broad because
% some exported reactance/inductance values are negative by definition.
cfg.maxAbsValue = 1.0e12;
cfg.maxCleanedRelativeJump = 0.50;

% Frequency bands used later by Python and included in QC metadata.
cfg.frequencyBands = [
    1, 50
    50, 200
    200, 500
    500, 1000
    1000, 2000
];

cfg.saveFigures = true;
cfg.saveMat = true;
end
