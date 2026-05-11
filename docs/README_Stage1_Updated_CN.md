# 更新后 Stage 1 全电学参数预处理说明

## 1. 总体逻辑树

```text
MFC_Stage1_Preprocess_RawSpectra
├─ 读取 MFC_Preprocess_Config
├─ 扫描目标实验文件夹
├─ 按 8 类电学参数识别 CSV
├─ 解析文件名得到温度、阶段、累计循环
├─ 对每个 CSV 的每个电学通道
│  ├─ 读入原始频率和值
│  ├─ MFC_Align_To_CommonGrid：对齐到 1:2000 Hz
│  ├─ MFC_PhysicsAware_OutlierMask：物理约束异常判别
│  ├─ 局部替换、滤波和平滑
│  ├─ 写入 Python 友好长表
│  └─ MFC_QC_Plots：输出清洗对比图
├─ attachBaselineRatios：计算相对基线 ratio
├─ computeChannelConsistency：检查阻抗-导纳一致性
├─ MFC_Write_HumanReadable_Workbooks：写人工宽表
└─ MFC_Write_QA_Report：写 JSON QA 报告
```

Stage 1 只负责预处理，不做寿命预测。它的目标是把原始 WaveForms CSV 变成可靠、可追溯、物理合理、Python 可稳定读取的数据。

## 2. 主入口：`MFC_Stage1_Preprocess_RawSpectra.m`

### 2.1 脚本作用

主入口脚本，完成全电学参数预处理端到端流程。

### 2.2 输入

无显式函数输入。脚本从 `MFC_Preprocess_Config()` 读取配置。

关键配置输入：

| 变量 | 含义 | 修改影响 |
|---|---|---|
| `cfg.targetFolder` | 原始实验 CSV 文件夹 | 改变读取的数据源 |
| `cfg.allowedSuffixes` | 允许处理的电学参数类型 | 增减 Stage 1 覆盖的数据类型 |
| `cfg.baselineTempC` | 基线温度，当前固定为 25 °C | 改变基线行的温度标注和 sheet 名 |
| `cfg.commonFreqHz` | 公共频率网格，当前为 `1:2000` | 改变所有输出频率点和 ratio 对齐基础 |
| `cfg.outputFolder` | 输出目录 | 改变长表、QC、Excel、图像输出位置 |

### 2.3 输出

| 输出文件 | 作用 |
---|---|
| `stage1_all_electrical_long_with_cycles.csv` | Python Stage 2 主输入长表 |
| `stage1_preprocess_qc.csv` | 每个文件/通道的清洗质量统计 |
| `stage1_channel_consistency_qc.csv` | 阻抗-导纳一致性检查 |
| `stage1_qa_report.json` | 阶段级 QA 汇总 |
| `stage1_human_<Metric>.xlsx` | 人工检查宽表 |
| `figs/*.png` | 每个通道清洗前后对比图 |

### 2.4 内部函数

#### `detectMetric(fileName, suffixes)`

作用：根据文件名后缀识别电学参数类型。

输入：

| 参数 | 类型 | 含义 |
|---|---|---|
| `fileName` | char/string | CSV 文件名 |
| `suffixes` | cell array | 允许的后缀列表 |

输出：

| 输出 | 含义 |
|---|---|
| `metric` | 识别出的类型，如 `Capacitance` |
| `ok` | 是否属于支持的电学参数 |

影响：如果 `cfg.allowedSuffixes` 不含某类参数，该类文件会被跳过。

#### `parseStateFromFileName(fileName, metric, cfg)`

作用：解析实验状态。

输出结构 `meta`：

| 字段 | 含义 |
|---|---|
| `sampleId` | 去掉后缀后的样本状态名 |
| `tempC` | 温度；基线为 `25` |
| `stage` | 同一温度下第几次退化；基线为 `0` |
| `cycles` | 累计循环数；基线为 `0` |
| `isBaseline` | 是否基线 |
| `stateLabel` | 状态标签 |

物理/实验含义：同一片 MFC 按温度顺序累计循环，因此 `cycles` 比单温度 `stage` 更适合后续疲劳建模。

#### `parseTemperatureStage(fileName)`

作用：从中文文件名中解析 `XX度第Y次退化`。

设计原因：避免在中文路径上做复杂字节级正则；使用 `strfind` 定位 `度/第/次`，再读取前后的数字。

#### `cleanAlignedSeries(freq, alignedValue, metric, channel, cfg)`

作用：对已经对齐到公共频率网格的数据做物理约束清洗。

输入：

| 参数 | 含义 |
|---|---|
| `freq` | 频率网格 |
| `alignedValue` | 对齐后的原始值 |
| `metric` | 电学参数类型 |
| `channel` | 通道名 |
| `cfg` | 清洗配置 |

输出：

| 输出 | 含义 |
|---|---|
| `cleanValue` | 清洗后的值 |
| `isOutlier` | 孤立异常点标记 |
| `isDistortion` | 非物理畸变标记 |
| `isNotchArtifact` | 仪器 notch 伪影标记 |
| `cleanMethod` | 清洗方法标签 |

数学核心：

局部 MAD 判别：

```text
|x_i - median(W_i)| > k * MAD(W_i)
```

其中 `W_i` 是以第 `i` 个频点为中心的局部窗口，`k=cfg.localMadSigma`。MAD 对孤立尖峰比标准差更稳健。

平滑：

- 先用局部中位数替换被标记点。
- 再用中值滤波抑制短脉冲噪声。
- 最后用 Savitzky-Golay 滤波保留谱线趋势。

物理原则：连续多个频点构成的峰谷可能是压电谐振/反谐振或相位跨越，不应被当作普通噪声抹平。

#### `isResonanceLike(~, x, cfg)`

作用：保护连续谱形变化。

物理含义：MFC 作为压电复合材料，电学谱在机电耦合频段可能出现连续的峰、谷、相位快速变化。这类变化反映真实的等效电路和机电耦合，不是孤立异常。

修改影响：

| 参数 | 影响 |
|---|---|
| `cfg.minPhysicalFeatureWidth` 增大 | 只有更宽的连续变化会被保护，清洗更激进 |
| `cfg.localMadSigma` 增大 | 更少点被认为是剧烈变化，清洗更保守 |

#### `buildLongBlock(...)`

作用：把单个文件、单个通道的频谱组织成长表块。

输出列：

```text
file, metric, channel, tempC, stage, cycles, isBaseline,
freqHz, rawValue, alignedValue, cleanValue, ratioToBaseline,
isOutlier, isDistortion, isNotchArtifact, cleanMethod
```

说明：`rawValue` 和 `alignedValue` 当前都对应公共频率网格上的原始对齐值；这样可以保证 Stage 2 Python 不需要处理不等长原始频率。

#### `attachBaselineRatios(T)`

作用：计算每个 `metric-channel` 的基线归一化。

公式：

```text
ratioToBaseline(f, T, N) = cleanValue(f, T, N) / cleanValue_baseline(f)
```

物理意义：消除不同通道绝对量纲影响，突出相对基线的变化。对电容而言，它能区分“温度增介电导致整体上升”和“损伤导致局部塌陷或衰减”。

注意：如果基线通道缺失或基线值接近 0，则 ratio 输出 `NaN`，避免无意义除法。

#### `summarizeQc(...)`

作用：为每个文件/通道输出 QC 统计。

关键输出：

| 字段 | 含义 |
|---|---|
| `missingCount` | 缺失点数量 |
| `outlierCount` | 异常点数量 |
| `distortionCount` | 畸变点数量 |
| `notchArtifactCount` | 仪器 notch 点数量 |
| `meanAbsCleaningDelta` | 平均清洗幅度 |
| `maxAbsCleaningDelta` | 最大清洗幅度 |

用途：人工判断某个文件是否被过度清洗。

#### `computeChannelConsistency(T)`

作用：检查 `Impedance Analyzer` 中的阻抗-导纳一致性。

公式：

```text
|Z| * |Y| ≈ 1
error = abs(|Z| * |Y| - 1)
```

物理原理：导纳是阻抗的倒数，理想情况下 `Y = 1/Z`。如果 `|Z|*|Y|` 长期偏离 1，可能说明导出通道、单位、清洗或仪器采样存在问题。

### 2.5 关键变量解释

| 变量 | 作用 | 改动影响 |
|---|---|---|
| `allRows` | 主长表累积容器 | 决定最终 Python 读取数据 |
| `qcRows` | 预处理 QC 容器 | 决定 QC 报告完整性 |
| `freqGrid` | 公共频率 | 影响所有后续 ratio 与宽表对齐 |
| `alignedValue` | 对齐后的原始谱值 | 清洗基础 |
| `cleanValue` | 清洗后谱值 | Stage 2 特征主要输入 |
| `ratioToBaseline` | 相对基线变化 | 后续损伤代理的重要基础 |
| `isOutlier` | 孤立异常 | 可用于排查尖峰噪声 |
| `isDistortion` | 非物理畸变 | 可用于排查单点跳变 |
| `isNotchArtifact` | 仪器 notch | 避免把工频/量程伪影误判为损伤 |

## 3. 配置：`MFC_Preprocess_Config.m`

### 3.1 作用

集中定义 Stage 1 的路径、处理对象、频率网格、异常判据、滤波参数、输出开关。

### 3.2 输入输出

无输入，输出 `cfg` 结构体。

### 3.3 参数组说明

#### 路径参数

| 参数 | 默认值 | 影响 |
|---|---|---|
| `targetFolder` | 目标实验文件夹 | 原始数据来源 |
| `outputFolder` | `outputs/stage1_preprocessed` | 所有 Stage 1 输出位置 |
| `figureFolder` | `outputs/stage1_preprocessed/figs` | QC 图输出位置 |

#### 数据类型参数

`allowedSuffixes` 包含 8 类参数。删除某项会让对应 CSV 完全不参与 Stage 1。

#### 频率参数

`commonFreqHz = (1:2000)'`。

公式上使用插值：

```text
x_aligned(f_grid) = pchip(f_raw, x_raw, f_grid)
```

`pchip` 比普通线性插值更平滑，同时比高阶样条更不容易振荡。

#### 异常判别参数

| 参数 | 增大后效果 | 减小后效果 |
|---|---|---|
| `hampelSigma` | 更少点被判异常 | 更多尖峰被处理 |
| `localMadSigma` | 更保守，保护谱形 | 更激进，可能误伤真实峰谷 |
| `globalMadSigma` | 更少全局异常 | 更容易处理极端值 |
| `maxCleanedRelativeJump` | 容许更大清洗偏移 | 更容易标记过度清洗 |
| `minPhysicalFeatureWidth` | 更严格保护宽谱特征 | 更容易把窄峰也保护下来 |

#### 仪器 notch 参数

`instrumentNotchCentersHz = [50, 350]`。

物理/仪器含义：

- 50 Hz 通常对应工频干扰。
- 350 Hz 附近可能对应仪器量程或采样伪影。

这些点如果在所有文件中反复出现，更可能是仪器伪影，不应作为损伤特征。

## 4. 辅助模块

### 4.1 `MFC_Attach_CumulativeCycles(tempC, stage)`

作用：把温度和阶段映射成累计循环数。

输入：

| 参数 | 含义 |
|---|---|
| `tempC` | 温度 |
| `stage` | 当前温度下第几次退化 |

输出：

| 输出 | 含义 |
|---|---|
| `cycles` | 累计循环数 |

公式：

```text
cycles = (temperature_index - 1) * 3 + stage
```

其中温度顺序为 `[70, 80, 90, 100, 110, 120]`。

基线不调用该公式，直接为 `0`。

### 4.2 `MFC_Align_To_CommonGrid(freq, value, cfg)`

作用：去掉无效点和重复频率，并插值到公共频率网格。

输入：

| 参数 | 含义 |
|---|---|
| `freq` | 原始频率 |
| `value` | 原始通道值 |
| `cfg.commonFreqHz` | 目标频率网格 |

输出：

| 输出 | 含义 |
|---|---|
| `freqGrid` | 公共频率 |
| `alignedValue` | 插值后的值 |
| `duplicateCount` | 重复频率数 |

数学公式：

```text
alignedValue = interp1(freqUnique, valueUnique, freqGrid, 'pchip')
```

影响：频率对齐是计算逐点 ratio、跨文件比较和人类宽表对齐的前提。

### 4.3 `MFC_PhysicsAware_OutlierMask(freq, value, metric, channel, cfg)`

作用：在清洗前生成异常、畸变、notch 标记。

输入：

| 参数 | 含义 |
|---|---|
| `freq` | 公共频率 |
| `value` | 对齐值 |
| `metric` | 电学参数类型 |
| `channel` | 通道名 |
| `cfg` | 判别配置 |

输出：

| 输出 | 含义 |
|---|---|
| `isOutlier` | 孤立尖峰或无效值 |
| `isDistortion` | 非物理跳变 |
| `isNotchArtifact` | 仪器 notch |
| `methodCode` | 判别方法 |
| `workingValue` | 相位展开后的工作序列 |

主要子函数：

- `prepareSeries`：对相位通道执行 unwrap。
- `isPhaseSeries`：判断是否相位通道。
- `detectContinuousPhysicalFeature`：保护连续谱形。
- `detectInstrumentNotch`：识别 50/350 Hz 附近伪影。
- `detectNonphysicalJump`：识别单点非物理跳变。

相位展开公式：

```text
phase_unwrapped = rad2deg(unwrap(deg2rad(phase_deg)))
```

物理意义：相位在 ±180° 附近可能出现数值跳变，但真实相位是连续变化的；展开后再清洗能避免把相位跨越误判为异常。

### 4.4 `MFC_QC_Plots(...)`

作用：输出单通道清洗前后对比图。

输入包括频率、对齐值、清洗值、三类标记、文件名、参数类型、通道名、输出路径。

输出：PNG 图。

用途：人工判断是否过度平滑、是否误伤谐振点、notch 是否被正确标记。

### 4.5 `MFC_Write_HumanReadable_Workbooks(T, cfg)`

作用：生成按电学参数分类的人类可读 Excel。

输入：

| 参数 | 含义 |
|---|---|
| `T` | Stage 1 主长表 |
| `cfg` | 输出配置 |

输出：每个 `metric` 一个 workbook，每个温度一个 sheet。

列组织：

```text
freqHz
<channel>_s<stage>_N<cycles>_raw
<channel>_s<stage>_N<cycles>_clean
<channel>_s<stage>_N<cycles>_ratio
<channel>_s<stage>_N<cycles>_flag
```

影响：不参与算法建模，主要给人类审查。

### 4.6 `MFC_Write_QA_Report(T, qcRows, consistencyQc, cfg)`

作用：生成 JSON 汇总报告。

输出包含：

- 处理的参数类型。
- 通道列表。
- 温度列表。
- 循环列表。
- 长表行数。
- QC 行数。
- 输出路径。

该报告用于快速确认 Stage 1 是否完整执行。

## 5. 物理原则总结

### 5.1 不应清洗掉的真实物理现象

- 压电材料的谐振/反谐振峰谷。
- 相位连续跨越。
- 阻抗下降同时导纳上升的互补变化。
- 温度升高导致介电常数上升，从而电容整体上移。

### 5.2 应标记或替换的异常

- 单点孤立尖峰。
- 非物理单点跳变。
- `NaN/Inf` 或超出极宽物理范围的值。
- 50 Hz、350 Hz 附近反复出现的仪器 notch。

## 6. 对 Stage 2 Python 的约定

Stage 2 应读取：

```text
stage1_all_electrical_long_with_cycles.csv
```

建议使用字段：

| 字段 | 用途 |
|---|---|
| `cleanValue` | 主特征输入 |
| `alignedValue` | 需要保留高频抖动时使用 |
| `ratioToBaseline` | 相对基线损伤/漂移分析 |
| `isOutlier/isDistortion/isNotchArtifact` | 特征权重或排除策略 |
| `cycles` | 累计疲劳循环主变量 |
| `tempC` | 热历史变量 |

不要在 Python 中重新做原始 CSV 清洗；Python 只消费 Stage 1 输出。
