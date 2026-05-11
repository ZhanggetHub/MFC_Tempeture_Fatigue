# MFC 温度疲劳 Stage 1 全电学参数预处理

本仓库当前重点是 `Stage 1`：对 `0/45/0/45/0` 编织纹 D31 MFC 的温度疲劳实验电学谱数据进行 MATLAB 预处理，输出给后续 Python Stage 2 使用的标准化数据。

## 当前版本做什么

- 处理 8 类 Digilent WaveForms 导出 CSV：
  - `Capacitance`
  - `Impedance`
  - `Inductance`
  - `Phase`
  - `Admittance`
  - `Current`
  - `Voltage`
  - `Impedance Analyzer`
- 基线固定为 `25 °C`，`stage=0`，`cycles=0`。
- 退化数据按累计循环协议编号：70 °C 第 1/2/3 次为 `cycles=1/2/3`，一直到 120 °C 第 2 次为 `cycles=17`。
- 输出两类文件：
  - 给 Python 读取的统一长表。
  - 给人工检查的按电学参数分类的宽表 Excel。
- 清洗逻辑采用“物理约束优先”：保留压电材料真实谐振/反谐振、相位跨越、阻抗-导纳互补变化，只处理孤立尖峰、非物理跳变、仪器 notch、无效值。

## 运行方式

在 MATLAB 中进入本项目根目录后执行：

```matlab
MFC_Stage1_Preprocess_RawSpectra
```

输出目录：

```text
outputs/stage1_preprocessed/
```

## 主要输出

Python Stage 2 主输入：

```text
outputs/stage1_preprocessed/stage1_all_electrical_long_with_cycles.csv
```

固定列名：

```text
file, metric, channel, tempC, stage, cycles, isBaseline,
freqHz, rawValue, alignedValue, cleanValue, ratioToBaseline,
isOutlier, isDistortion, isNotchArtifact, cleanMethod
```

人工检查宽表：

```text
stage1_human_Capacitance.xlsx
stage1_human_Admittance.xlsx
stage1_human_Impedance_Analyzer.xlsx
...
```

质量控制输出：

```text
stage1_preprocess_qc.csv
stage1_channel_consistency_qc.csv
stage1_qa_report.json
figs/*.png
```

## 中文详细文档

- [更新后 Stage 1 全电学参数预处理说明](docs/README_Stage1_Updated_CN.md)
- [更新前 Stage 1 脚本说明](docs/README_Stage1_Previous_CN.md)

## 注意

当前环境若 MATLAB 许可证不可用，会出现 `License checkout failed`，这不是脚本逻辑错误。代码已按 MATLAB 运行方式组织，需在有 MATLAB 授权的环境中生成真实输出。
