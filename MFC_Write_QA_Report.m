function MFC_Write_QA_Report(T, qcRows, consistencyQc, cfg)
% Write a compact JSON QA report for Stage 1.

report = struct();
report.generatedBy = 'MFC_Stage1_Preprocess_RawSpectra';
report.targetFolder = cfg.targetFolder;
report.baselineTempC = cfg.baselineTempC;
report.allowedSuffixes = cfg.allowedSuffixes;
report.commonFrequencyMinHz = min(cfg.commonFreqHz);
report.commonFrequencyMaxHz = max(cfg.commonFreqHz);
report.commonFrequencyCount = numel(cfg.commonFreqHz);
report.longTableRows = height(T);
report.qcRows = height(qcRows);
report.consistencyRows = height(consistencyQc);
report.metrics = cellstr(unique(T.metric, 'stable'));
report.channels = cellstr(unique(T.channel, 'stable'));
report.temperatures = unique(T.tempC)';
report.cycles = unique(T.cycles)';
report.outputLongTable = fullfile(cfg.outputFolder, 'stage1_all_electrical_long_with_cycles.csv');
report.outputPreprocessQc = fullfile(cfg.outputFolder, 'stage1_preprocess_qc.csv');
report.outputConsistencyQc = fullfile(cfg.outputFolder, 'stage1_channel_consistency_qc.csv');

jsonText = jsonencode(report, 'PrettyPrint', true);
fid = fopen(fullfile(cfg.outputFolder, 'stage1_qa_report.json'), 'w', 'n', 'UTF-8');
if fid < 0
    error('Could not write QA report.');
end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', jsonText);
end
