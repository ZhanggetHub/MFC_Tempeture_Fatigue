function MFC_QC_Plots(freq, raw, cleaned, isOutlier, sourceFile, channel, outPath)
% Save a compact before/after QC plot for one spectrum channel.

fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1100, 650]);
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(freq, raw, '-', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.8); hold on;
plot(freq, cleaned, 'r-', 'LineWidth', 1.1);
if any(isOutlier)
    scatter(freq(isOutlier), raw(isOutlier), 16, 'b', 'filled', 'MarkerFaceAlpha', 0.65);
end
grid on;
xlabel('Frequency (Hz)');
ylabel(channel, 'Interpreter', 'none');
title(sourceFile, 'Interpreter', 'none');
legend({'Raw','Cleaned','Outlier'}, 'Location', 'best');

nexttile;
plot(freq, cleaned - raw, 'k-', 'LineWidth', 0.8); hold on;
if any(isOutlier)
    scatter(freq(isOutlier), cleaned(isOutlier) - raw(isOutlier), 14, 'b', 'filled');
end
grid on;
xlabel('Frequency (Hz)');
ylabel('Cleaned - Raw');
title('Cleaning residual');

exportgraphics(fig, char(outPath), 'Resolution', 180);
close(fig);
end
