# 更新前 Stage 1 脚本说明

本文档记录本次更新前 `HEAD` 中的 Stage 1 预处理脚本逻辑，便于与全电学参数版本对照。

## 1. 更新前总体逻辑

```text
MFC_Stage1_Preprocess_RawSpectra
├─ 读取 MFC_Preprocess_Config
├─ 扫描目标文件夹 CSV
├─ 只处理配置中的 5 类参数
│  ├─ Capacitance
│  ├─ Impedance
│  ├─ Inductance
│  ├─ Phase
│  └─ Admittance
├─ 跳过 WaveForms 30 行头部
├─ 对每个文件每个通道
│  ├─ 去重频率
│  ├─ 清洗序列 cleanSeries
│  ├─ 追加到 cleaned_spectra.csv
│  └─ 输出 QC 图
└─ 写出 cleaned_spectra.csv / cleaned_spectra.mat / preprocess_qc.csv
```

更新前版本已经有多参数雏形，但仍有几个限制：

- 没覆盖 `Current`、`Voltage`、`Impedance Analyzer`。
- `cycle_index` 是单温度阶段，不是累计循环 `cycles=0..17`。
- 输出列名是旧 Python 包使用的 `sample_id/source_file/temperature_c/frequency_hz` 风格，不是本次统一的 Stage 2 长表。
- 没有人类可读宽表。
- 没有显式 `ratioToBaseline`。
- 异常判别较偏数学滤波，没有充分保护谐振/反谐振等压电物理响应。

## 2. 更新前 `MFC_Preprocess_Config.m`

### 2.1 作用

定义旧版 Stage 1 的路径、支持参数、滤波窗口和异常阈值。

### 2.2 输出变量

输出 `cfg` 结构体。

### 2.3 关键变量

| 变量 | 更新前含义 | 修改影响 |
|---|---|---|
| `targetFolder` | 原始实验文件夹 | 决定扫描位置 |
| `outputFolder` | 输出目录 | 决定 `cleaned_spectra.csv` 等位置 |
| `figureFolder` | QC 图目录 | 决定图像输出位置 |
| `allowedSuffixes` | 仅包含 5 类参数 | 不在列表中的 CSV 会被跳过 |
| `phaseSuffixes` | 相位参数列表 | 决定是否相位展开 |
| `unwrapPhaseDegrees` | 是否 unwrap 相位 | 影响 `Trace th (deg)` 的处理 |
| `headerLines` | WaveForms 元数据行数，默认 30 | 改错会导致读表错位 |
| `expectedRowsPerFile` | 期望频点数，默认 2000 | 用于 QC |
| `hampelWindow` | Hampel 窗口 | 增大后对宽峰更敏感，计算更平滑 |
| `hampelSigma` | Hampel 阈值 | 增大更保守，减小更激进 |
| `medianWindow` | 中值滤波窗口 | 增大可抑制更多尖峰，但可能压平窄峰 |
| `sgWindow` | Savitzky-Golay 窗口 | 增大更平滑，可能损失局部细节 |
| `sgOrder` | Savitzky-Golay 多项式阶数 | 增大可保留曲率，但可能过拟合 |
| `localMadSigma` | 局部 MAD 阈值 | 控制局部异常判定强度 |
| `globalMadSigma` | 全局 MAD 阈值 | 控制极端值判定 |
| `maxAbsValue` | 物理极宽上限 | 超出会被标记无效 |
| `maxCleanedRelativeJump` | 清洗后相对变化阈值 | 用于标记清洗幅度过大 |

## 3. 更新前主脚本函数

### 3.1 `detectMetric(fileName, suffixes)`

作用：识别 CSV 后缀是否属于支持类型。

输入：

| 参数 | 含义 |
|---|---|
| `fileName` | 文件名 |
| `suffixes` | 支持参数类型 |

输出：

| 输出 | 含义 |
|---|---|
| `metric` | 匹配到的电学参数 |
| `ok` | 是否处理该文件 |

限制：旧版 `suffixes` 不包含 8 类全参数，因此会漏掉 Current/Voltage/Impedance Analyzer。

### 3.2 `parseStateFromFileName(fileName)`

作用：解析文件名中的基线或温度阶段。

输出 `meta` 字段：

| 字段 | 含义 |
|---|---|
| `sampleId` | 样本状态名 |
| `layup` | 固定为 `0-45-0-45-0` |
| `mfcMode` | 固定为 `D31` |
| `temperatureC` | 温度；基线为 25 |
| `cycleIndex` | 文件名中的第几次退化 |
| `stateLabel` | 状态标签 |

限制：`cycleIndex` 在旧版中不是累计循环，只是同温度内的阶段。例如 80 °C 第 1 次仍为 `cycleIndex=1`，没有表达它其实是全实验累计第 4 次。

### 3.3 `cleanSeries(values, metric, channel, cfg)`

作用：清洗单个通道。

输入：

| 参数 | 含义 |
|---|---|
| `values` | 原始通道序列 |
| `metric` | 参数类型 |
| `channel` | 通道名 |
| `cfg` | 配置 |

输出：

| 输出 | 含义 |
|---|---|
| `cleaned` | 清洗后值 |
| `flag` | 异常标记 |
| `methodCode` | 清洗方法 |

数学公式：

局部 MAD：

```text
|x_i - median(W_i)| > k_local * MAD(W_i)
```

全局 MAD：

```text
|x_i - median(x)| > k_global * MAD(x)
```

Hampel：

```text
x_i 被局部窗口中位数判为离群点
```

处理流程：

1. `NaN/Inf/超大值` 标记为无效。
2. 对缺失值线性填充。
3. 局部 MAD、全局 MAD、Hampel 判别异常。
4. 用局部中位数替换异常。
5. 中值滤波。
6. Savitzky-Golay 平滑。
7. 如果清洗前后差异过大，再标记 `large_cleaning_delta`。

局限：没有显式识别谐振/反谐振连续谱形，也没有单独区分 `isDistortion` 和 `isNotchArtifact`。

### 3.4 `prepareSeriesForCleaning(values, metric, channel, cfg)`

作用：对相位通道进行预处理。

相位展开公式：

```text
working = rad2deg(unwrap(deg2rad(values)))
```

物理意义：相位角在 ±180° 处可能发生数值跳变，但实际物理相位连续，unwrap 可以减少误判。

### 3.5 `isPhaseSeries(metric, channel, cfg)`

作用：判断是否相位通道。

判据：

```text
metric 属于 cfg.phaseSuffixes
或 channel 名包含 th
```

### 3.6 `summarizeQc(fileName, metric, channel, meta, freq, raw, cleaned, flag, duplicateCount, expectedRows)`

作用：输出每个文件/通道的 QC 行。

输出字段：

| 字段 | 含义 |
|---|---|
| `sample_id` | 样本状态 |
| `source_file` | 原文件 |
| `state_label` | 状态标签 |
| `temperature_c` | 温度 |
| `cycle_index` | 同温度阶段 |
| `metric` | 参数类型 |
| `channel` | 通道 |
| `row_count` | 行数 |
| `freq_min/freq_max` | 频率范围 |
| `duplicate_frequency_count` | 重复频率数 |
| `missing_count` | 缺失值数量 |
| `outlier_count/outlier_rate` | 异常数量/比例 |
| `mean_abs_cleaning_delta` | 平均清洗幅度 |
| `max_abs_cleaning_delta` | 最大清洗幅度 |
| `row_count_ok` | 是否为预期 2000 行 |

## 4. 更新前输出结构

机器输出：

```text
cleaned_spectra.csv
cleaned_spectra.mat
preprocess_qc.csv
qc_plots/*.png
```

`cleaned_spectra.csv` 列：

```text
sample_id, source_file, layup, mfc_mode, state_label,
temperature_c, cycle_index, metric, channel, frequency_hz,
raw_value, cleaned_value, is_outlier, clean_method
```

## 5. 更新前版本与新版差异

| 方面 | 更新前 | 更新后 |
|---|---|---|
| 参数类型 | 5 类 | 8 类 |
| 循环变量 | `cycle_index` 单温度阶段 | `cycles` 全实验累计循环 |
| 基线温度 | 25 °C | 25 °C，显式固定 |
| 频率对齐 | 保留文件频率 | 统一 `1:2000 Hz` |
| ratio | 无 | `ratioToBaseline` |
| 异常类型 | `is_outlier` 单标记 | outlier/distortion/notch 三类 |
| 物理保护 | 较弱 | 显式保护谐振、相位跨越、阻抗-导纳互补 |
| 人类宽表 | 无 | 每类参数一个 workbook |
| Python 接口 | 旧列名 | ASCII 固定长表 |

## 6. 为什么需要升级

旧版适合作为快速清洗脚本，但面对 MFC 温度疲劳寿命预测，会遇到三类问题：

1. 只看部分电学参数容易误判损伤。电容上升可能是温度增介电，不一定是性能退化。
2. 没有累计循环数，就无法表达同一片 MFC 样品的热历史。
3. 物理响应和异常噪声需要分开。压电谐振、相位跨越、阻抗-导纳互补变化是材料/结构响应，不能简单按尖峰清掉。

新版 Stage 1 正是为了解决这些问题。
