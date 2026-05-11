function MFC_QC_Plots(freq, alignedValue, cleanValue, isOutlier, isDistortion, isNotchArtifact, sourceFile, metric, channel, outPath)
% Save a compact before/after QC plot for one electrical spectrum channel.

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1150, 720]);
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(freq, alignedValue, '-', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.8); hold on;
plot(freq, cleanValue, 'r-', 'LineWidth', 1.1);
if any(isOutlier)
    scatter(freq(isOutlier), alignedValue(isOutlier), 16, 'b', 'filled', 'MarkerFaceAlpha', 0.65);
end
if any(isDistortion)
    scatter(freq(isDistortion), alignedValue(isDistortion), 18, [0.90 0.45 0.05], 'filled', 'MarkerFaceAlpha', 0.65);
end
if any(isNotchArtifact)
    scatter(freq(isNotchArtifact), alignedValue(isNotchArtifact), 18, [0.25 0.55 0.25], 'filled', 'MarkerFaceAlpha', 0.65);
end
grid on;
xlabel('Frequency (Hz)');
ylabel(channel, 'Interpreter', 'none');
title(sprintf('%s | %s | %s', sourceFile, metric, channel), 'Interpreter', 'none');
legend({'Aligned','Cleaned','Outlier','Distortion','Notch artifact'}, 'Location', 'best');

nexttile;
plot(freq, cleanValue - alignedValue, 'k-', 'LineWidth', 0.8); hold on;
flag = isOutlier | isDistortion | isNotchArtifact;
if any(flag)
    scatter(freq(flag), cleanValue(flag) - alignedValue(flag), 14, 'b', 'filled');
end
grid on;
xlabel('Frequency (Hz)');
ylabel('Cleaned - aligned');
title('Cleaning residual');

exportgraphics(fig, char(outPath), 'Resolution', 180);
close(fig);
end
