function [freqGrid, alignedValue, duplicateCount] = MFC_Align_To_CommonGrid(freq, value, cfg)
% Align one raw spectrum to the common 1:2000 Hz grid.

freq = double(freq(:));
value = double(value(:));
valid = isfinite(freq) & isfinite(value);
freq = freq(valid);
value = value(valid);

[freq, order] = sort(freq);
value = value(order);
[freqUnique, uniqueIdx] = unique(freq, 'stable');
duplicateCount = numel(freq) - numel(freqUnique);
valueUnique = value(uniqueIdx);

freqGrid = cfg.commonFreqHz(:);
if numel(freqUnique) < 2
    alignedValue = nan(size(freqGrid));
    return;
end

alignedValue = interp1(freqUnique, valueUnique, freqGrid, 'pchip', NaN);
end
