function [isOutlier, isDistortion, isNotchArtifact, methodCode, workingValue] = MFC_PhysicsAware_OutlierMask(freq, value, metric, channel, cfg)
% Physics-aware abnormal point detection for piezoelectric electrical spectra.
%
% The detector is intentionally conservative. Resonance/anti-resonance peaks,
% phase transitions, and reciprocal impedance/admittance behavior can be real
% piezoelectric responses, so only isolated spikes, non-physical points, and
% known instrument artifacts are selected for replacement.

freq = double(freq(:));
value = double(value(:));
workingValue = prepareSeries(value, metric, channel, cfg);

n = numel(workingValue);
methodCode = strings(n, 1);
methodCode(:) = "none";

invalid = isnan(workingValue) | isinf(workingValue) | abs(workingValue) > cfg.maxAbsValue;

filled = fillmissing(workingValue, 'linear', 'EndValues', 'nearest');
localMedian = movmedian(filled, cfg.localWindow, 'omitnan');
localMad = movmad(filled, cfg.localWindow, 1, 'omitnan');
localMad(localMad == 0 | isnan(localMad)) = median(localMad(localMad > 0), 'omitnan');
if isempty(localMad) || isnan(localMad(1)); localMad(:) = eps; end
localSpike = abs(filled - localMedian) > cfg.localMadSigma .* max(localMad, eps);

globalMedian = median(filled, 'omitnan');
globalMad = mad(filled, 1);
if globalMad == 0 || isnan(globalMad); globalMad = eps; end
globalSpike = abs(filled - globalMedian) > cfg.globalMadSigma * globalMad;

try
    hampelSpike = isoutlier(filled, 'movmedian', cfg.hampelWindow, ...
        'ThresholdFactor', cfg.hampelSigma);
catch
    hampelSpike = false(size(filled));
end

resonanceProtected = detectContinuousPhysicalFeature(filled, cfg);
isolatedSpike = (localSpike | globalSpike | hampelSpike) & ~resonanceProtected;

isNotchArtifact = detectInstrumentNotch(freq, filled, localMedian, cfg);
isDistortion = detectNonphysicalJump(filled, cfg) & ~resonanceProtected;
isOutlier = invalid | isolatedSpike;

methodCode(invalid) = "invalid_or_physical_limit";
methodCode(isolatedSpike & methodCode == "none") = "isolated_spike";
methodCode(isDistortion & methodCode == "none") = "nonphysical_jump";
methodCode(isNotchArtifact & methodCode == "none") = "instrument_notch";

if isPhaseSeries(metric, channel, cfg) && cfg.unwrapPhaseDegrees
    methodCode(methodCode == "none") = "phase_unwrapped";
end
end

function workingValue = prepareSeries(value, metric, channel, cfg)
workingValue = value;
if isPhaseSeries(metric, channel, cfg) && cfg.unwrapPhaseDegrees
    finiteMask = isfinite(value);
    if any(finiteMask)
        workingValue(finiteMask) = rad2deg(unwrap(deg2rad(value(finiteMask))));
    end
end
end

function tf = isPhaseSeries(metric, channel, cfg)
tf = any(strcmpi(metric, cfg.phaseSuffixes)) || contains(lower(channel), 'th');
end

function protected = detectContinuousPhysicalFeature(x, cfg)
dx = abs(diff(x));
protected = false(size(x));
if numel(dx) < cfg.minPhysicalFeatureWidth
    return;
end
madDx = mad(dx, 1);
if madDx == 0 || isnan(madDx); madDx = eps; end
active = [false; dx > median(dx, 'omitnan') + cfg.localMadSigma * madDx];

runStart = 0;
for k = 1:numel(active)
    if active(k) && runStart == 0
        runStart = k;
    elseif (~active(k) || k == numel(active)) && runStart > 0
        runEnd = k - 1;
        if active(k) && k == numel(active); runEnd = k; end
        if runEnd - runStart + 1 >= cfg.minPhysicalFeatureWidth
            padStart = max(1, runStart - 2);
            padEnd = min(numel(protected), runEnd + 2);
            protected(padStart:padEnd) = true;
        end
        runStart = 0;
    end
end
end

function notch = detectInstrumentNotch(freq, x, localMedian, cfg)
notch = false(size(freq));
for c = 1:numel(cfg.instrumentNotchCentersHz)
    center = cfg.instrumentNotchCentersHz(c);
    near = abs(freq - center) <= cfg.instrumentNotchHalfWidthHz;
    if any(near)
        residual = abs(x - localMedian);
        scale = mad(residual, 1);
        if scale == 0 || isnan(scale); scale = eps; end
        notch = notch | (near & residual > median(residual, 'omitnan') + 3 * scale);
    end
end
end

function jump = detectNonphysicalJump(x, cfg)
dx = [0; abs(diff(x))];
madDx = mad(dx, 1);
if madDx == 0 || isnan(madDx); madDx = eps; end
jump = dx > median(dx, 'omitnan') + cfg.globalMadSigma * madDx;

% Single-sample jumps are suspicious; broad runs are likely physical response.
runStart = 0;
for k = 1:numel(jump)
    if jump(k) && runStart == 0
        runStart = k;
    elseif (~jump(k) || k == numel(jump)) && runStart > 0
        runEnd = k - 1;
        if jump(k) && k == numel(jump); runEnd = k; end
        if runEnd - runStart + 1 >= cfg.minPhysicalFeatureWidth
            jump(runStart:runEnd) = false;
        end
        runStart = 0;
    end
end
end
