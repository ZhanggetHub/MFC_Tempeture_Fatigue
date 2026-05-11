function MFC_Write_HumanReadable_Workbooks(T, cfg)
% Write one human-readable workbook per electrical metric.
%
% Each workbook contains one sheet per temperature. Rows are common frequency
% points, and columns are grouped by channel/stage/cycle and value kind.

metrics = unique(T.metric, 'stable');
for m = 1:numel(metrics)
    metric = metrics(m);
    metricRows = T(T.metric == metric, :);
    workbook = fullfile(cfg.outputFolder, ['stage1_human_' char(makeSafeName(metric)) '.xlsx']);
    if exist(workbook, 'file'); delete(workbook); end

    temps = unique(metricRows.tempC);
    temps = sort(temps(:)');
    for ti = 1:numel(temps)
        tempC = temps(ti);
        tempRows = metricRows(metricRows.tempC == tempC, :);
        if tempC == cfg.baselineTempC && any(tempRows.isBaseline)
            sheetName = sprintf('Baseline_%dC', cfg.baselineTempC);
        else
            sheetName = sprintf('%dC', tempC);
        end

        wide = table(cfg.commonFreqHz(:), 'VariableNames', {'freqHz'});
        channels = unique(tempRows.channel, 'stable');
        for c = 1:numel(channels)
            channel = channels(c);
            chRows = tempRows(tempRows.channel == channel, :);
            states = unique(chRows(:, {'stage','cycles','isBaseline'}), 'rows');
            states = sortrows(states, {'stage','cycles'});
            for s = 1:height(states)
                stateRows = chRows(chRows.stage == states.stage(s) & chRows.cycles == states.cycles(s), :);
                if isempty(stateRows); continue; end
                [~, order] = sort(stateRows.freqHz);
                stateRows = stateRows(order, :);
                prefix = makeSafeName(sprintf('%s_s%d_N%d', char(channel), states.stage(s), states.cycles(s)));
                wide.([char(prefix) '_raw']) = stateRows.rawValue;
                wide.([char(prefix) '_clean']) = stateRows.cleanValue;
                wide.([char(prefix) '_ratio']) = stateRows.ratioToBaseline;
                wide.([char(prefix) '_flag']) = double(stateRows.isOutlier | stateRows.isDistortion | stateRows.isNotchArtifact);
            end
        end

        writetable(wide, workbook, 'Sheet', sheetName);
    end
end
end

function s = makeSafeName(x)
s = string(x);
s = regexprep(s, '[^A-Za-z0-9]+', '_');
s = regexprep(s, '^_+|_+$', '');
if strlength(s) == 0
    s = "unknown";
end
if strlength(s) > 40
    s = extractBefore(s, 41);
end
end
