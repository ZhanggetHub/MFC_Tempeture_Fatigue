function cfg = MFC_Preprocess_Config()
% Configuration for Stage 1 all-electrical-parameter preprocessing.
%
% Stage 1 is a MATLAB-only raw-data preprocessing layer. It exports a
% Python-friendly long table for Stage 2 and human-readable workbooks for
% manual review.

cfg.targetFolder = '0 45 0 45 0 编织纹复材D31 MFC-温度导致传感性能退化试验';
cfg.outputFolder = fullfile(pwd, 'outputs', 'stage1_preprocessed');
cfg.figureFolder = fullfile(cfg.outputFolder, 'figs');

cfg.allowedSuffixes = { ...
    'Capacitance', ...
    'Impedance', ...
    'Inductance', ...
    'Phase', ...
    'Admittance', ...
    'Current', ...
    'Voltage', ...
    'Impedance Analyzer'};
cfg.phaseSuffixes = {'Phase'};

cfg.baselineTempC = 25;
cfg.headerLines = 30;
cfg.expectedRowsPerFile = 2000;
cfg.commonFreqHz = (1:2000)';

% Filtering parameters. Windows are odd sample counts.
cfg.hampelWindow = 11;
cfg.hampelSigma = 4.0;
cfg.medianWindow = 5;
cfg.sgWindow = 21;
cfg.sgOrder = 3;

% Physics-aware outlier rules. The sigma values are deliberately conservative:
% it is safer to preserve true piezoelectric resonance/anti-resonance behavior
% than to flatten meaningful electromechanical response.
cfg.localWindow = 21;
cfg.localMadSigma = 7.0;
cfg.globalMadSigma = 14.0;
cfg.maxAbsValue = 1.0e12;
cfg.maxCleanedRelativeJump = 0.50;
cfg.minPhysicalFeatureWidth = 5;

% Instrument artifacts reported in the previous capacitance-only Stage 1.
cfg.instrumentNotchCentersHz = [50, 350];
cfg.instrumentNotchHalfWidthHz = 2;
cfg.suppressInstrumentNotches = true;

% Phase channels need unwrapping before local smoothing.
cfg.unwrapPhaseDegrees = true;

% Output controls.
cfg.saveFigures = true;
cfg.saveMat = true;
cfg.writeHumanReadableWorkbooks = true;
cfg.writeUtf8BomCsv = true;

% Frequency bands included in QA metadata and expected by Stage 2.
cfg.frequencyBands = [
    1, 50
    50, 200
    200, 500
    500, 1000
    1000, 2000
];
end
