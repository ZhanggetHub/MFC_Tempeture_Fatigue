%% Stage 1: all-electrical-parameter preprocessing for MFC temperature fatigue.
%
% Raw input:
%   WaveForms CSV exports in cfg.targetFolder.
%
% Main outputs:
%   outputs/stage1_preprocessed/stage1_all_electrical_long_with_cycles.csv
%   outputs/stage1_preprocessed/stage1_preprocess_qc.csv
%   outputs/stage1_preprocessed/stage1_channel_consistency_qc.csv
%   outputs/stage1_preprocessed/stage1_qa_report.json
%   outputs/stage1_preprocessed/stage1_human_<Metric>.xlsx
%
% This stage intentionally does not train life models. It only creates clean,
% traceable, physics-aware spectra for Stage 2 Python.

clear; clc;

cfg = MFC_Preprocess_Config();
if ~exist(cfg.outputFolder, 'dir'); mkdir(cfg.outputFolder); end
if cfg.saveFigures && ~exist(cfg.figureFolder, 'dir'); mkdir(cfg.figureFolder); end

targetDir = fullfile(pwd, cfg.targetFolder);
if ~exist(targetDir, 'dir')
    error('Target folder not found: %s', targetDir);
end

files = dir(fullfile(targetDir, '*.csv'));
allRows = table();
qcRows = table();

fprintf('Stage 1 all-electrical preprocessing\n');
fprintf('Target folder: %s\n', targetDir);

for i = 1:numel(files)
    fileName = files(i).name;
    [metric, ok] = detectMetric(fileName, cfg.allowedSuffixes);
    if ~ok
        continue;
    end

    filePath = fullfile(files(i).folder, fileName);
    meta = parseStateFromFileName(fileName, metric, cfg);

    raw = readtable(filePath, 'NumHeaderLines', cfg.headerLines, ...
        'VariableNamingRule', 'preserve');
    if isempty(raw) || width(raw) < 2
        warning('Skipping empty or malformed file: %s', fileName);
        continue;
    end

    freq = raw{:, 1};
    if ~isnumeric(freq); freq = str2double(string(freq)); end

    numericCols = raw.Properties.VariableNames(2:end);
    for c = 1:numel(numericCols)
        channel = numericCols{c};
        rawValue = raw{:, c + 1};
        if ~isnumeric(rawValue); rawValue = str2double(string(rawValue)); end

        [freqGrid, alignedValue, duplicateCount] = MFC_Align_To_CommonGrid(freq, rawValue, cfg);

        [cleanValue, isOutlier, isDistortion, isNotchArtifact, cleanMethod] = ...
            cleanAlignedSeries(freqGrid, alignedValue, metric, channel, cfg);

        block = buildLongBlock(fileName, metric, channel, meta, freqGrid, ...
            rawValue, alignedValue, cleanValue, isOutlier, isDistortion, ...
            isNotchArtifact, cleanMethod);
        allRows = [allRows; block]; %#ok<AGROW>

        qc = summarizeQc(fileName, metric, channel, meta, freqGrid, alignedValue, ...
            cleanValue, isOutlier, isDistortion, isNotchArtifact, duplicateCount, cfg);
        qcRows = [qcRows; qc]; %#ok<AGROW>

        if cfg.saveFigures
            safeName = regexprep(sprintf('%s_%s_%s', meta.sampleId, metric, channel), ...
                '[<>:"/\\|?*\s]+', '_');
            outFig = fullfile(cfg.figureFolder, [safeName '.png']);
            MFC_QC_Plots(freqGrid, alignedValue, cleanValue, isOutlier, ...
                isDistortion, isNotchArtifact, fileName, metric, channel, outFig);
        end
    end
end

if isempty(allRows)
    error('No supported electrical CSV files were found.');
end

allRows = sortrows(allRows, {'metric','tempC','stage','channel','freqHz'});
allRows = attachBaselineRatios(allRows);
qcRows = sortrows(qcRows, {'metric','tempC','stage','channel'});

longCsv = fullfile(cfg.outputFolder, 'stage1_all_electrical_long_with_cycles.csv');
qcCsv = fullfile(cfg.outputFolder, 'stage1_preprocess_qc.csv');
writeTableUtf8(allRows, longCsv, cfg);
writeTableUtf8(qcRows, qcCsv, cfg);

consistencyQc = computeChannelConsistency(allRows);
writeTableUtf8(consistencyQc, fullfile(cfg.outputFolder, 'stage1_channel_consistency_qc.csv'), cfg);

if cfg.saveMat
    stage1_all_electrical_long = allRows; %#ok<NASGU>
    stage1_preprocess_qc = qcRows; %#ok<NASGU>
    stage1_channel_consistency_qc = consistencyQc; %#ok<NASGU>
    save(fullfile(cfg.outputFolder, 'stage1_all_electrical_long_with_cycles.mat'), ...
        'stage1_all_electrical_long', 'stage1_preprocess_qc', ...
        'stage1_channel_consistency_qc', 'cfg', '-v7.3');
end

if cfg.writeHumanReadableWorkbooks
    MFC_Write_HumanReadable_Workbooks(allRows, cfg);
end

MFC_Write_QA_Report(allRows, qcRows, consistencyQc, cfg);

fprintf('Done. Long-table rows: %d\n', height(allRows));
fprintf('QC rows: %d\n', height(qcRows));
fprintf('Output folder: %s\n', cfg.outputFolder);

function [metric, ok] = detectMetric(fileName, suffixes)
metric = '';
ok = false;
for k = 1:numel(suffixes)
    suffix = suffixes{k};
    if endsWith(fileName, ['-' suffix '.csv'])
        metric = suffix;
        ok = true;
        return;
    end
end
end

function meta = parseStateFromFileName(fileName, metric, cfg)
base = erase(fileName, '.csv');
base = erase(base, ['-' metric]);
meta.sampleId = char(base);
meta.tempC = cfg.baselineTempC;
meta.stage = 0;
meta.cycles = 0;
meta.isBaseline = true;
meta.stateLabel = sprintf('Baseline_%dC', cfg.baselineTempC);

tempStage = parseTemperatureStage(fileName);
if ~isempty(tempStage)
    meta.tempC = tempStage(1);
    meta.stage = tempStage(2);
    meta.cycles = MFC_Attach_CumulativeCycles(meta.tempC, meta.stage);
    meta.isBaseline = false;
    meta.stateLabel = sprintf('%dC_stage_%d_cycle_%d', meta.tempC, meta.stage, meta.cycles);
elseif contains(fileName, '基线')
    meta.tempC = cfg.baselineTempC;
    meta.stage = 0;
    meta.cycles = 0;
    meta.isBaseline = true;
end
end

function tempStage = parseTemperatureStage(fileName)
% Avoid regexp over full CJK file names. MATLAB handles this well, and it is
% more robust on Windows Chinese paths than byte-oriented parsing.
tempStage = [];
degreePos = strfind(fileName, '度');
diPos = strfind(fileName, '第');
ciPos = strfind(fileName, '次');
if isempty(degreePos) || isempty(diPos) || isempty(ciPos)
    return;
end

d = degreePos(1);
startTemp = d - 1;
while startTemp >= 1 && fileName(startTemp) >= '0' && fileName(startTemp) <= '9'
    startTemp = startTemp - 1;
end
tempText = fileName(startTemp + 1:d - 1);

di = diPos(find(diPos > d, 1, 'first'));
if isempty(di)
    return;
end
ci = ciPos(find(ciPos > di, 1, 'first'));
if isempty(ci) || ci <= di + 1
    return;
end
stageText = fileName(di + 1:ci - 1);

tempC = str2double(tempText);
stage = str2double(stageText);
if isfinite(tempC) && isfinite(stage)
    tempStage = [tempC, stage];
end
end

function [cleanValue, isOutlier, isDistortion, isNotchArtifact, cleanMethod] = cleanAlignedSeries(freq, alignedValue, metric, channel, cfg)
[candidateOutlier, isDistortion, isNotchArtifact, methodCode, workingValue] = ...
    MFC_PhysicsAware_OutlierMask(freq, alignedValue, metric, channel, cfg);

filled = fillmissing(workingValue, 'linear', 'EndValues', 'nearest');
if all(isnan(filled))
    cleanValue = workingValue;
    isOutlier = candidateOutlier;
    cleanMethod = methodCode;
    return;
end

localMedian = movmedian(filled, cfg.localWindow, 'omitnan');
replaceMask = candidateOutlier | isDistortion | (isNotchArtifact & cfg.suppressInstrumentNotches);
replaced = filled;
replaced(replaceMask) = localMedian(replaceMask);
replaced = fillmissing(replaced, 'linear', 'EndValues', 'nearest');

try
    med = medfilt1(replaced, cfg.medianWindow, 'truncate');
catch
    med = movmedian(replaced, cfg.medianWindow, 'omitnan');
end

try
    if numel(med) >= cfg.sgWindow
        cleanValue = sgolayfilt(med, cfg.sgOrder, cfg.sgWindow);
    else
        cleanValue = med;
    end
catch
    cleanValue = smoothdata(med, 'movmean', cfg.sgWindow);
end

largeJump = abs(cleanValue - filled) > cfg.maxCleanedRelativeJump .* max(abs(filled), eps);
largeJump = largeJump & ~isResonanceLike(freq, filled, cfg);

isOutlier = candidateOutlier | largeJump;
methodCode(largeJump & methodCode == "none") = "large_cleaning_delta";
cleanMethod = methodCode;
end

function tf = isResonanceLike(~, x, cfg)
dx = abs(diff(x));
if numel(dx) < cfg.minPhysicalFeatureWidth
    tf = false(size(x));
    return;
end
madDx = mad(dx, 1);
if madDx == 0 || isnan(madDx); madDx = eps; end
active = [false; dx > median(dx, 'omitnan') + cfg.localMadSigma * madDx];
tf = false(size(x));
runStart = 0;
for k = 1:numel(active)
    if active(k) && runStart == 0
        runStart = k;
    elseif (~active(k) || k == numel(active)) && runStart > 0
        runEnd = k - 1;
        if active(k) && k == numel(active); runEnd = k; end
        if runEnd - runStart + 1 >= cfg.minPhysicalFeatureWidth
            tf(runStart:runEnd) = true;
        end
        runStart = 0;
    end
end
end

function block = buildLongBlock(fileName, metric, channel, meta, freq, rawOriginal, alignedValue, cleanValue, isOutlier, isDistortion, isNotchArtifact, cleanMethod)
n = numel(freq);
% The long table is aligned to the common frequency grid. rawValue therefore
% stores the raw channel after frequency-grid alignment; alignedValue is kept
% as a separate explicit column for the Stage 2 contract.
rawValue = alignedValue;
block = table( ...
    repmat(string(fileName), n, 1), ...
    repmat(string(metric), n, 1), ...
    repmat(string(channel), n, 1), ...
    repmat(meta.tempC, n, 1), ...
    repmat(meta.stage, n, 1), ...
    repmat(meta.cycles, n, 1), ...
    repmat(meta.isBaseline, n, 1), ...
    freq(:), rawValue(:), alignedValue(:), cleanValue(:), ...
    nan(n, 1), isOutlier(:), isDistortion(:), isNotchArtifact(:), cleanMethod(:), ...
    'VariableNames', {'file','metric','channel','tempC','stage','cycles', ...
    'isBaseline','freqHz','rawValue','alignedValue','cleanValue', ...
    'ratioToBaseline','isOutlier','isDistortion','isNotchArtifact','cleanMethod'});
end

function T = attachBaselineRatios(T)
T.ratioToBaseline(:) = NaN;
pairs = unique(T(:, {'metric','channel'}));
for i = 1:height(pairs)
    metric = pairs.metric(i);
    channel = pairs.channel(i);
    idx = T.metric == metric & T.channel == channel;
    bidx = idx & T.isBaseline;
    if ~any(bidx)
        continue;
    end
    base = T(bidx, {'freqHz','cleanValue'});
    [~, ord] = sort(base.freqHz);
    base = base(ord, :);
    denom = interp1(base.freqHz, base.cleanValue, T.freqHz(idx), 'linear', NaN);
    valid = isfinite(denom) & abs(denom) > eps;
    ratio = nan(sum(idx), 1);
    vals = T.cleanValue(idx);
    ratio(valid) = vals(valid) ./ denom(valid);
    tmp = find(idx);
    T.ratioToBaseline(tmp) = ratio;
end
end

function qc = summarizeQc(fileName, metric, channel, meta, freq, alignedValue, cleanValue, isOutlier, isDistortion, isNotchArtifact, duplicateCount, cfg)
delta = cleanValue(:) - alignedValue(:);
qc = table(string(fileName), string(metric), string(channel), meta.tempC, meta.stage, ...
    meta.cycles, meta.isBaseline, numel(freq), min(freq), max(freq), duplicateCount, ...
    sum(isnan(alignedValue)), sum(isOutlier), mean(isOutlier), sum(isDistortion), ...
    mean(isDistortion), sum(isNotchArtifact), mean(isNotchArtifact), ...
    mean(abs(delta), 'omitnan'), max(abs(delta), [], 'omitnan'), ...
    cfg.expectedRowsPerFile, numel(freq) == cfg.expectedRowsPerFile, ...
    'VariableNames', {'file','metric','channel','tempC','stage','cycles', ...
    'isBaseline','rowCount','freqMin','freqMax','duplicateFrequencyCount', ...
    'missingCount','outlierCount','outlierRate','distortionCount', ...
    'distortionRate','notchArtifactCount','notchArtifactRate', ...
    'meanAbsCleaningDelta','maxAbsCleaningDelta','expectedRows','rowCountOk'});
end

function consistency = computeChannelConsistency(T)
analyzer = T(T.metric == "Impedance Analyzer", :);
if isempty(analyzer)
    consistency = table();
    return;
end

files = unique(analyzer.file, 'stable');
consistency = table();
for i = 1:numel(files)
    fileRows = analyzer(analyzer.file == files(i), :);
    zRows = fileRows(fileRows.channel == "Trace |Z| (Ohm)", :);
    yRows = fileRows(fileRows.channel == "Trace |Y| (S)", :);
    if ~isempty(zRows) && ~isempty(yRows)
        [commonFreq, iz, iy] = intersect(zRows.freqHz, yRows.freqHz);
        err = abs(zRows.cleanValue(iz) .* yRows.cleanValue(iy) - 1);
        err = err(isfinite(err));
        if ~isempty(err)
            consistency = [consistency; table(files(i), zRows.tempC(1), zRows.stage(1), ...
                zRows.cycles(1), string('Zmag_times_Ymag_minus_1'), mean(err), max(err), ...
                numel(commonFreq), 'VariableNames', {'file','tempC','stage','cycles', ...
                'checkName','meanAbsError','maxAbsError','pointCount'})]; %#ok<AGROW>
        end
    end
end
end

function writeTableUtf8(T, path, cfg)
if cfg.writeUtf8BomCsv
    writetable(T, path, 'Encoding', 'UTF-8');
else
    writetable(T, path);
end
end
