function cycles = MFC_Attach_CumulativeCycles(tempC, stage)
% Map the cumulative-cycle protocol A used by the MFC temperature experiment.
%
% Baseline is handled by the caller as cycles=0. For degradation files:
% 70C stage 1/2/3 -> cycles 1/2/3, 80C -> 4/5/6, ..., 120C stage 1/2 -> 16/17.

temps = [70, 80, 90, 100, 110, 120];
idx = find(temps == tempC, 1);
if isempty(idx) || stage < 1
    cycles = NaN;
    return;
end

cycles = (idx - 1) * 3 + stage;
end
