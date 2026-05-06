%% Stage 1: preprocess raw MFC electrical spectra.
% Outputs:
%   outputs/stage1_preprocessed/cleaned_spectra.csv
%   outputs/stage1_preprocessed/cleaned_spectra.mat
%   outputs/stage1_preprocessed/preprocess_qc.csv
%   outputs/stage1_preprocessed/qc_plots/*.png
%
% Supported WaveForms exports:
%   Capacitance, Impedance, Inductance, Phase, Admittance

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

fprintf('Scanning %s\n', targetDir);

for i = 1:numel(files)
    fileName = files(i).name;
    [metric, ok] = detectMetric(fileName, cfg.allowedSuffixes);
    if ~ok
        continue;
    end

    filePath = fullfile(files(i).folder, files(i).name);
    meta = parseStateFromFileName(fileName);
    raw = readtable(filePath, 'NumHeaderLines', cfg.headerLines, ...
        'VariableNamingRule', 'preserve');

    if isempty(raw) || width(raw) < 2
        warning('Skipping empty or malformed file: %s', fileName);
        continue;
    end

    freq = raw{:, 1};
    if ~isnumeric(freq); freq = str2double(string(freq)); end

    [uniqueFreq, uniqueIdx] = unique(freq, 'stable');
    duplicateCount = numel(freq) - numel(uniqueFreq);
    raw = raw(uniqueIdx, :);
    freq = uniqueFreq;

    numericCols = raw.Properties.VariableNames(2:end);
    for c = 1:numel(numericCols)
        colName = numericCols{c};
        values = raw{:, c + 1};
        if ~isnumeric(values); values = str2double(string(values)); end

        [cleaned, flag, methodCode] = cleanSeries(values, metric, colName, cfg);

        sampleId = repmat(string(meta.sampleId), numel(freq), 1);
        fileCol = repmat(string(fileName), numel(freq), 1);
        layup = repmat(string(meta.layup), numel(freq), 1);
        mfcMode = repmat(string(meta.mfcMode), numel(freq), 1);
        metricCol = repmat(string(metric), numel(freq), 1);
        channelCol = repmat(string(colName), numel(freq), 1);
        stateLabel = repmat(string(meta.stateLabel), numel(freq), 1);
        temperatureC = repmat(meta.temperatureC, numel(freq), 1);
        cycleIndex = repmat(meta.cycleIndex, numel(freq), 1);

        block = table(sampleId, fileCol, layup, mfcMode, stateLabel, ...
            temperatureC, cycleIndex, metricCol, channelCol, freq, ...
            values, cleaned, flag, methodCode, ...
            'VariableNames', {'sample_id','source_file','layup','mfc_mode', ...
            'state_label','temperature_c','cycle_index','metric','channel', ...
            'frequency_hz','raw_value','cleaned_value','is_outlier','clean_method'});
        allRows = [allRows; block]; %#ok<AGROW>

        qc = summarizeQc(fileName, metric, colName, meta, freq, values, cleaned, ...
            flag, duplicateCount, cfg.expectedRowsPerFile);
        qcRows = [qcRows; qc]; %#ok<AGROW>

        if cfg.saveFigures
            safeName = regexprep(sprintf('%s_%s_%s', meta.sampleId, metric, colName), ...
                '[<>:"/\\|?*\s]+', '_');
            outFig = fullfile(cfg.figureFolder, [safeName '.png']);
            MFC_QC_Plots(freq, values, cleaned, flag, fileName, metric, colName, outFig);
        end
    end
end

allRows = sortrows(allRows, {'metric','temperature_c','cycle_index','channel','frequency_hz'});
qcRows = sortrows(qcRows, {'metric','temperature_c','cycle_index','channel'});

writetable(allRows, fullfile(cfg.outputFolder, 'cleaned_spectra.csv'));
writetable(qcRows, fullfile(cfg.outputFolder, 'preprocess_qc.csv'));

if cfg.saveMat
    cleaned_spectra = allRows; %#ok<NASGU>
    preprocess_qc = qcRows; %#ok<NASGU>
    save(fullfile(cfg.outputFolder, 'cleaned_spectra.mat'), ...
        'cleaned_spectra', 'preprocess_qc', 'cfg', '-v7.3');
end

fprintf('Done. Cleaned rows: %d\n', height(allRows));
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

function meta = parseStateFromFileName(fileName)
base = erase(fileName, '.csv');
base = regexprep(base, '-(Capacitance|Impedance|Inductance|Phase|Admittance)$', '');
meta.sampleId = base;
meta.layup = '0-45-0-45-0';
meta.mfcMode = 'D31';
meta.temperatureC = 25;
meta.cycleIndex = 0;
meta.stateLabel = 'baseline';

tok = regexp(fileName, '(\d+)度第(\d+)次退化', 'tokens', 'once');
if ~isempty(tok)
    meta.temperatureC = str2double(tok{1});
    meta.cycleIndex = str2double(tok{2});
    meta.stateLabel = sprintf('%dC_cycle_%d', meta.temperatureC, meta.cycleIndex);
elseif contains(fileName, '基线')
    meta.stateLabel = 'baseline';
end
end

function [cleaned, flag, methodCode] = cleanSeries(values, metric, channel, cfg)
values = double(values(:));
workingValues = prepareSeriesForCleaning(values, metric, channel, cfg);
flag = false(size(values));
methodCode = strings(size(values));
methodCode(:) = "none";

bad = isnan(workingValues) | isinf(workingValues) | abs(workingValues) > cfg.maxAbsValue;
flag = flag | bad;
methodCode(bad) = "invalid_or_physical_limit";

filled = fillmissing(workingValues, 'linear', 'EndValues', 'nearest');
if all(isnan(filled))
    cleaned = workingValues;
    return;
end

localMedian = movmedian(filled, cfg.localWindow, 'omitnan');
localMad = movmad(filled, cfg.localWindow, 1, 'omitnan');
localMad(localMad == 0 | isnan(localMad)) = median(localMad(localMad > 0), 'omitnan');
if isnan(localMad(1)); localMad(:) = eps; end
localOutlier = abs(filled - localMedian) > cfg.localMadSigma .* max(localMad, eps);

globalMedian = median(filled, 'omitnan');
globalMad = mad(filled, 1);
if globalMad == 0 || isnan(globalMad); globalMad = eps; end
globalOutlier = abs(filled - globalMedian) > cfg.globalMadSigma * globalMad;

flag = flag | localOutlier | globalOutlier;
methodCode(localOutlier) = "local_mad";
methodCode(globalOutlier) = "global_mad";

try
    hampelFlag = isoutlier(filled, 'movmedian', cfg.hampelWindow, ...
        'ThresholdFactor', cfg.hampelSigma);
catch
    hampelFlag = false(size(filled));
end
flag = flag | hampelFlag;
methodCode(hampelFlag) = "hampel";

replaced = filled;
replaced(flag) = localMedian(flag);
replaced = fillmissing(replaced, 'linear', 'EndValues', 'nearest');

try
    med = medfilt1(replaced, cfg.medianWindow, 'truncate');
catch
    med = movmedian(replaced, cfg.medianWindow, 'omitnan');
end

try
    if numel(med) >= cfg.sgWindow
        cleaned = sgolayfilt(med, cfg.sgOrder, cfg.sgWindow);
    else
        cleaned = med;
    end
catch
    cleaned = smoothdata(med, 'movmean', cfg.sgWindow);
end

largeJump = abs(cleaned - filled) > cfg.maxCleanedRelativeJump .* max(abs(filled), eps);
flag = flag | largeJump;
methodCode(largeJump & methodCode == "none") = "large_cleaning_delta";

if isPhaseSeries(metric, channel, cfg) && cfg.unwrapPhaseDegrees
    methodCode(methodCode == "none") = "phase_unwrap_smooth";
end
end

function workingValues = prepareSeriesForCleaning(values, metric, channel, cfg)
workingValues = values;
if isPhaseSeries(metric, channel, cfg) && cfg.unwrapPhaseDegrees
    finiteMask = isfinite(values);
    if any(finiteMask)
        workingValues(finiteMask) = rad2deg(unwrap(deg2rad(values(finiteMask))));
    end
end
end

function tf = isPhaseSeries(metric, channel, cfg)
tf = any(strcmpi(metric, cfg.phaseSuffixes)) || contains(lower(channel), 'th');
end

function qc = summarizeQc(fileName, metric, channel, meta, freq, raw, cleaned, flag, duplicateCount, expectedRows)
raw = double(raw(:));
cleaned = double(cleaned(:));
delta = cleaned - raw;
qc = table(string(meta.sampleId), string(fileName), string(meta.stateLabel), ...
    meta.temperatureC, meta.cycleIndex, string(metric), string(channel), ...
    numel(freq), min(freq), max(freq), duplicateCount, sum(isnan(raw)), ...
    sum(flag), mean(flag), mean(abs(delta), 'omitnan'), max(abs(delta), [], 'omitnan'), ...
    expectedRows, numel(freq) == expectedRows, ...
    'VariableNames', {'sample_id','source_file','state_label','temperature_c', ...
    'cycle_index','metric','channel','row_count','freq_min','freq_max', ...
    'duplicate_frequency_count','missing_count','outlier_count','outlier_rate', ...
    'mean_abs_cleaning_delta','max_abs_cleaning_delta','expected_rows', ...
    'row_count_ok'});
end
