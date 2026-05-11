# MFC_Stage1_Preprocess_RawSpectra.m 中文说明

`MFC_Stage1_Preprocess_RawSpectra.m` 是 Stage 1 全电学参数预处理主入口。

详细说明已统一整理到：

- [更新后 Stage 1 全电学参数预处理说明](docs/README_Stage1_Updated_CN.md)
- [更新前 Stage 1 脚本说明](docs/README_Stage1_Previous_CN.md)

## 当前主入口职责

- 扫描目标实验文件夹中的 8 类 WaveForms CSV。
- 解析中文文件名中的基线、温度、退化阶段。
- 注入累计循环数 `cycles=0..17`。
- 将所有通道对齐到 `1:2000 Hz`。
- 执行物理约束异常判别和保守清洗。
- 输出 Python 友好长表。
- 输出每类电学参数的人类可读 Excel 宽表。
- 输出 QC 表、通道一致性表、QA JSON 和清洗对比图。

## 运行命令

```matlab
MFC_Stage1_Preprocess_RawSpectra
```

## 主输出

```text
outputs/stage1_preprocessed/stage1_all_electrical_long_with_cycles.csv
outputs/stage1_preprocessed/stage1_preprocess_qc.csv
outputs/stage1_preprocessed/stage1_channel_consistency_qc.csv
outputs/stage1_preprocessed/stage1_qa_report.json
outputs/stage1_preprocessed/stage1_human_<Metric>.xlsx
```

## 长表固定列名

```text
file, metric, channel, tempC, stage, cycles, isBaseline,
freqHz, rawValue, alignedValue, cleanValue, ratioToBaseline,
isOutlier, isDistortion, isNotchArtifact, cleanMethod
```

这些列名刻意使用 ASCII 风格，便于 Python Stage 2 稳定读取。
