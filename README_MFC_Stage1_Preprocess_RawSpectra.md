# README: MFC_Stage1_Preprocess_RawSpectra.m

## 1. 脚本定位

`MFC_Stage1_Preprocess_RawSpectra.m` 是 MATLAB 数据预处理主脚本。  
它是整个温度疲劳寿命预测流程的第一阶段入口，负责把 Digilent WaveForms 导出的原始 CSV 变成 Python 可以直接读取的清洗数据。

本脚本处理的数据类型仅包括：

- `Capacitance`
- `Impedance`
- `Inductance`

它不会处理 `Voltage`、`Current`、`Phase`、`Admittance` 等其他 CSV。

## 2. 输入与输出

### 输入

原始实验目录：

```text
0 45 0 45 0 编织纹复材D31 MFC-温度导致传感性能退化试验
```

该目录由 `MFC_Preprocess_Config.m` 中的 `cfg.targetFolder` 指定。

### 输出

默认输出目录：

```text
outputs/stage1_preprocessed
```

输出文件：

| 文件 | 作用 |
|---|---|
| `cleaned_spectra.csv` | 长表格式清洗数据，Python 特征提取直接读取它。 |
| `cleaned_spectra.mat` | MATLAB 格式备份，包含 `cleaned_spectra`、`preprocess_qc`、`cfg`。 |
| `preprocess_qc.csv` | 每个文件、每个通道的质量控制摘要。 |
| `qc_plots/*.png` | 每个通道清洗前后对比图。 |

## 3. 总体逻辑树

```text
MFC_Stage1_Preprocess_RawSpectra
├─ 初始化环境
│  ├─ clear; clc
│  └─ 读取 cfg 配置
├─ 创建输出目录
├─ 定位目标实验文件夹
├─ 扫描 CSV 文件
├─ 遍历每一个 CSV
│  ├─ 判断是否是允许后缀
│  ├─ 解析文件名中的温度/循环/基线信息
│  ├─ 跳过 WaveForms 元数据读取表格
│  ├─ 检查空表或列数异常
│  ├─ 提取频率列
│  ├─ 删除重复频率
│  └─ 遍历每一个数值通道
│     ├─ 提取原始数值
│     ├─ cleanSeries 清洗谱线
│     ├─ 整理成长表 block
│     ├─ summarizeQc 生成 QC 摘要
│     └─ MFC_QC_Plots 输出对比图
├─ 汇总排序
├─ 写出 CSV
├─ 可选写出 MAT
└─ 打印完成信息

局部函数
├─ detectMetric
├─ parseStateFromFileName
├─ cleanSeries
└─ summarizeQc
```

## 4. 主变量说明

| 变量 | 来源 | 作用 |
|---|---|---|
| `cfg` | `MFC_Preprocess_Config()` | 配置结构体，包含路径、滤波参数、阈值、保存开关。 |
| `targetDir` | `fullfile(pwd, cfg.targetFolder)` | 原始 CSV 所在完整路径。 |
| `files` | `dir(...)` | 目标目录下全部 CSV 文件信息。 |
| `allRows` | `table()` | 汇总全部清洗后的长表数据。 |
| `qcRows` | `table()` | 汇总每个通道的 QC 质量控制结果。 |
| `fileName` | `files(i).name` | 当前处理的 CSV 文件名。 |
| `metric` | `detectMetric` | 当前文件类型：`Capacitance`、`Impedance` 或 `Inductance`。 |
| `ok` | `detectMetric` | 是否属于允许处理的文件类型。 |
| `filePath` | `fullfile(...)` | 当前 CSV 的完整路径。 |
| `meta` | `parseStateFromFileName` | 从文件名解析出的实验状态元数据。 |
| `raw` | `readtable(...)` | 读取出来的原始表格数据。 |
| `freq` | `raw{:,1}` | 频率列，单位 Hz。 |
| `uniqueFreq` | `unique(...)` | 去重后的频率列。 |
| `uniqueIdx` | `unique(...)` | 保留的唯一频率行索引。 |
| `duplicateCount` | 计算值 | 重复频率数量，用于 QC。 |
| `numericCols` | `raw.Properties.VariableNames(2:end)` | 除频率列外的所有数值通道名。 |
| `colName` | `numericCols{c}` | 当前通道名。 |
| `values` | `raw{:, c+1}` | 当前通道原始数值。 |
| `cleaned` | `cleanSeries` | 清洗后的数值。 |
| `flag` | `cleanSeries` | 异常点逻辑标记。 |
| `methodCode` | `cleanSeries` | 异常点/清洗方法标签。 |
| `block` | `table(...)` | 当前文件当前通道整理后的长表数据块。 |
| `qc` | `summarizeQc` | 当前文件当前通道的质量控制摘要。 |
| `safeName` | `regexprep(...)` | 可安全用于图片文件名的字符串。 |
| `outFig` | `fullfile(...)` | QC 图片输出路径。 |

## 5. 输出长表字段说明

`cleaned_spectra.csv` 中每一行代表“一个实验状态、一个通道、一个频率点”。

| 字段 | 含义 |
|---|---|
| `sample_id` | 去除后缀后的样本状态名。 |
| `source_file` | 原始 CSV 文件名。 |
| `layup` | 铺层/编织结构，这里固定为 `0-45-0-45-0`。 |
| `mfc_mode` | MFC 工作模式，这里固定为 `D31`。 |
| `state_label` | 状态标签，如 `baseline`、`100C_cycle_2`。 |
| `temperature_c` | 温度，单位 °C。基线默认 25。 |
| `cycle_index` | 退化次数。基线为 0。 |
| `metric` | 数据类型：电容、阻抗或电感。 |
| `channel` | 通道名，如 `Trace Cs (F)`。 |
| `frequency_hz` | 频率，单位 Hz。 |
| `raw_value` | 原始值。 |
| `cleaned_value` | 清洗后数值。 |
| `is_outlier` | 是否被判为异常点。 |
| `clean_method` | 异常或清洗方法标签。 |

## 6. 函数说明

### 6.1 `detectMetric(fileName, suffixes)`

作用：判断当前文件是否属于允许处理的三类后缀。

输入：

- `fileName`：当前 CSV 文件名。
- `suffixes`：允许后缀列表。

输出：

- `metric`：匹配到的类型名。
- `ok`：是否匹配成功。

判断规则：

```text
如果文件名以 -Capacitance.csv 结尾，则 metric = Capacitance
如果文件名以 -Impedance.csv 结尾，则 metric = Impedance
如果文件名以 -Inductance.csv 结尾，则 metric = Inductance
否则 ok = false，主循环跳过
```

### 6.2 `parseStateFromFileName(fileName)`

作用：从中文文件名解析温度、退化次数和基线状态。

默认值：

- `temperatureC = 25`
- `cycleIndex = 0`
- `stateLabel = baseline`

识别规则：

- 匹配 `(\d+)度第(\d+)次退化`，例如 `100度第2次退化`。
- 如果匹配成功，则温度为 `100`，循环为 `2`。
- 如果文件名包含 `基线`，则保持基线状态。

### 6.3 `cleanSeries(values, cfg)`

作用：对一个通道的一条频谱曲线进行异常值识别、替换、滤波和平滑。

核心步骤：

```text
原始值
├─ 转为列向量 double
├─ 标记 NaN/Inf/极端物理异常
├─ 线性填补缺失值
├─ 局部 MAD 异常检测
├─ 全局 MAD 异常检测
├─ Hampel / moving median 异常检测
├─ 用局部中位数替换异常点
├─ 中值滤波
├─ Savitzky-Golay 平滑
└─ 检查清洗前后变化是否过大
```

输出：

- `cleaned`：清洗后的谱线。
- `flag`：异常点标记。
- `methodCode`：每个点的异常来源或清洗方法。

### 6.4 `summarizeQc(...)`

作用：生成单个文件、单个通道的质量控制摘要。

输出字段包括：

- 行数。
- 频率最小值/最大值。
- 重复频率数量。
- 缺失值数量。
- 异常点数量。
- 异常点比例。
- 清洗前后平均绝对差。
- 清洗前后最大绝对差。
- 是否满足 2000 行频点要求。

## 7. 逐行/逐段说明

| 行号 | 功能说明 |
|---:|---|
| 1 | 文件标题注释，说明这是 Stage 1，用于预处理 MFC 电容、阻抗、电感频谱。 |
| 2-6 | 列出本脚本将生成的四类输出。 |
| 8 | 清空工作区变量并清空命令行窗口。 |
| 10 | 调用配置函数，得到 `cfg`。 |
| 11 | 如果输出目录不存在，就创建输出目录。 |
| 12 | 如果开启保存图片且图片目录不存在，就创建图片目录。 |
| 14 | 将当前工作目录 `pwd` 与目标文件夹名拼成完整路径。 |
| 15-17 | 如果目标实验目录不存在，立即报错并停止，避免后续空处理。 |
| 19 | 扫描目标目录下所有 `.csv` 文件。 |
| 20 | 创建空表，用于累积全部清洗后的长表数据。 |
| 21 | 创建空表，用于累积质量控制结果。 |
| 23 | 在命令行打印当前正在扫描的目录。 |
| 25 | 开始遍历每一个 CSV 文件。 |
| 26 | 取出当前文件名。 |
| 27 | 调用 `detectMetric` 判断文件是否为三类目标文件之一。 |
| 28-30 | 如果不是目标后缀，跳过该文件。 |
| 32 | 生成当前 CSV 的完整路径。 |
| 33 | 调用 `parseStateFromFileName` 解析温度、循环次数、基线等元数据。 |
| 34-35 | 读取 CSV 表格，跳过前 30 行元数据，并保留原始列名。 |
| 37-40 | 如果读到空表或列数不足，发出警告并跳过。 |
| 42 | 提取第一列作为频率列。 |
| 43 | 如果频率列不是数值型，则转成字符串后再转成 double。 |
| 45 | 用 `unique(...,'stable')` 获取不重复频率，并保持原始顺序。 |
| 46 | 计算重复频率数量。 |
| 47 | 原始表格只保留唯一频率对应的行。 |
| 48 | 更新频率列为去重后的频率。 |
| 50 | 获取所有数值通道列名，排除第一列频率。 |
| 51 | 开始遍历当前文件里的每一个数值通道。 |
| 52 | 取出当前通道名。 |
| 53 | 取出当前通道的原始值。 |
| 54 | 如果原始值不是数值型，则转成 double。 |
| 56 | 调用 `cleanSeries` 得到清洗值、异常标记和方法标签。 |
| 58-66 | 把文件级元数据扩展成与频率点数量相同的列向量，方便组成长表。 |
| 68-73 | 把当前通道数据整理成 `block` 表，字段名固定为 Python 后续读取所需字段。 |
| 74 | 将当前通道的 `block` 追加到总表 `allRows`。 |
| 76-77 | 调用 `summarizeQc` 生成当前通道 QC 摘要。 |
| 78 | 将当前 QC 摘要追加到 `qcRows`。 |
| 80 | 判断是否需要保存 QC 图片。 |
| 81-82 | 把样本名、数据类型、通道名拼成图片名，并替换非法文件名字符。 |
| 83 | 生成完整图片保存路径。 |
| 84 | 调用 `MFC_QC_Plots` 保存清洗前后对比图。 |
| 86 | 结束通道循环。 |
| 87 | 结束文件循环。 |
| 89 | 对总清洗数据按类型、温度、循环、通道、频率排序。 |
| 90 | 对 QC 表按类型、温度、循环、通道排序。 |
| 92 | 写出 `cleaned_spectra.csv`。 |
| 93 | 写出 `preprocess_qc.csv`。 |
| 95 | 判断是否需要保存 `.mat`。 |
| 96 | 将 `allRows` 复制为变量 `cleaned_spectra`，用于保存到 MAT。 |
| 97 | 将 `qcRows` 复制为变量 `preprocess_qc`，用于保存到 MAT。 |
| 98-99 | 保存 `.mat` 文件，包含清洗数据、QC 数据和配置。`-v7.3` 适合较大数据。 |
| 100 | 结束 MAT 保存判断。 |
| 102 | 打印清洗后总行数。 |
| 103 | 打印 QC 表行数。 |
| 104 | 打印输出目录。 |
| 106 | 定义局部函数 `detectMetric`。 |
| 107 | 初始化 `metric` 为空字符串。 |
| 108 | 初始化 `ok=false`。 |
| 109 | 遍历允许后缀。 |
| 110 | 取出当前候选后缀。 |
| 111 | 判断文件名是否以 `-后缀.csv` 结尾。 |
| 112 | 如果匹配，保存当前类型名。 |
| 113 | 设置 `ok=true`。 |
| 114 | 找到匹配后立即返回。 |
| 116-117 | 结束循环和函数。 |
| 119 | 定义局部函数 `parseStateFromFileName`。 |
| 120 | 删除文件名末尾 `.csv`。 |
| 121 | 删除末尾数据类型后缀，得到样本状态名。 |
| 122 | 保存样本 ID。 |
| 123 | 写入固定铺层信息 `0-45-0-45-0`。 |
| 124 | 写入固定 MFC 模式 `D31`。 |
| 125 | 默认温度设为 25°C，代表基线室温。 |
| 126 | 默认循环次数设为 0。 |
| 127 | 默认状态标签为 `baseline`。 |
| 129 | 用正则表达式识别 `XX度第Y次退化`。 |
| 130 | 如果成功匹配温度和循环次数。 |
| 131 | 将温度字符串转成数字。 |
| 132 | 将循环次数字符串转成数字。 |
| 133 | 生成状态标签，如 `100C_cycle_2`。 |
| 134-135 | 如果没有匹配但文件名含 `基线`，保持基线标签。 |
| 136-137 | 结束条件和函数。 |
| 139 | 定义局部函数 `cleanSeries`。 |
| 140 | 将输入值转为 double 列向量。 |
| 141 | 初始化异常点标记，全为 false。 |
| 142 | 初始化方法标签数组。 |
| 143 | 默认方法标签为 `none`。 |
| 145 | 标记 NaN、Inf、超过物理上限的点。 |
| 146 | 将这些点合并进异常点标记。 |
| 147 | 为这些点写入方法标签 `invalid_or_physical_limit`。 |
| 149 | 对缺失值做线性填补，两端用最近值。 |
| 150-153 | 如果整条曲线全是 NaN，则无法清洗，直接返回原值。 |
| 155 | 计算局部移动中位数。 |
| 156 | 计算局部移动 MAD。 |
| 157 | 将 0 或 NaN 的 MAD 替换为有效 MAD 中位数。 |
| 158 | 如果第一个 MAD 仍为 NaN，则全部设为 `eps`，避免除零。 |
| 159 | 根据局部中位数和 MAD 判断局部异常点。 |
| 161 | 计算全局中位数。 |
| 162 | 计算全局 MAD。 |
| 163 | 如果全局 MAD 不可用，则设为 `eps`。 |
| 164 | 根据全局中位数和 MAD 判断全局异常点。 |
| 166 | 合并局部和全局异常点。 |
| 167 | 局部异常点标记方法为 `local_mad`。 |
| 168 | 全局异常点标记方法为 `global_mad`。 |
| 170 | 开始尝试调用 MATLAB 内置 `isoutlier`。 |
| 171-172 | 用移动中位数方式执行 Hampel 类异常检测。 |
| 173-175 | 如果当前 MATLAB 版本或工具箱不支持，则跳过该检测。 |
| 176 | 合并 Hampel 异常点。 |
| 177 | Hampel 异常点标记方法为 `hampel`。 |
| 179 | 创建替换用曲线。 |
| 180 | 将异常点替换为局部中位数。 |
| 181 | 对替换后的曲线再次填补缺失值。 |
| 183 | 开始尝试中值滤波。 |
| 184 | 优先使用 `medfilt1` 做中值滤波。 |
| 185-187 | 若无该函数，则退回 `movmedian`。 |
| 189 | 开始尝试 Savitzky-Golay 平滑。 |
| 190 | 判断数据点数是否足够使用设定窗口。 |
| 191 | 使用 `sgolayfilt` 平滑曲线。 |
| 192-194 | 如果点数不足，则不做 Savitzky-Golay，直接使用中值滤波结果。 |
| 195-197 | 如果 `sgolayfilt` 不可用，则退回移动均值平滑。 |
| 199 | 判断清洗后与填补后原始曲线的相对变化是否超过阈值。 |
| 200 | 将过大变化点也合并进异常标记。 |
| 201 | 对尚未有标签的过大变化点标记为 `large_cleaning_delta`。 |
| 202 | 结束 `cleanSeries`。 |
| 204 | 定义局部函数 `summarizeQc`。 |
| 205 | 将原始值转为 double 列向量。 |
| 206 | 将清洗值转为 double 列向量。 |
| 207 | 计算清洗残差 `cleaned - raw`。 |
| 208-217 | 创建 QC 表，包含文件名、状态、温度、循环、频率范围、异常率、清洗差异和行数检查。 |
| 218 | 结束 `summarizeQc`。 |

## 8. 数据质量控制逻辑

本脚本不会静默删除异常点，而是：

1. 保留原始值到 `raw_value`。
2. 保存清洗值到 `cleaned_value`。
3. 用 `is_outlier` 标记异常。
4. 用 `clean_method` 标记异常来源。
5. 在 `preprocess_qc.csv` 中汇总异常比例。
6. 在 QC 图中显示异常点。

这样后续 Python 建模既可以使用干净数据，也可以把异常点比例当作损伤风险特征。

## 9. 与 Python 阶段的接口

Python 阶段默认读取：

```text
outputs/stage1_preprocessed/cleaned_spectra.csv
```

字段名已经与 Python 的 `load_cleaned.py` 对齐，因此不建议随意修改 `VariableNames` 中的字段名。

