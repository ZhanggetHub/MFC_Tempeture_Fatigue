# README: MFC_Preprocess_Config.m

## 1. 脚本定位

`MFC_Preprocess_Config.m` 是整个 MATLAB 原始数据预处理流程的“配置中心”。  
它不直接读取 CSV，也不做滤波或绘图，而是集中定义：

- 目标实验数据文件夹位置。
- 输出文件夹位置。
- 允许处理的谱数据类型。
- WaveForms CSV 表头跳过行数。
- 异常值检测、滤波、平滑参数。
- 频段划分。
- 是否保存 QC 图片和 `.mat` 文件。

主脚本 `MFC_Stage1_Preprocess_RawSpectra.m` 会在第 10 行调用：

```matlab
cfg = MFC_Preprocess_Config();
```

调用后，主脚本通过 `cfg.xxx` 的形式读取本配置文件里的所有参数。

## 2. 总体逻辑树

```text
MFC_Preprocess_Config
├─ 创建配置结构体 cfg
├─ 指定输入/输出路径
│  ├─ targetFolder：原始实验数据目录
│  ├─ outputFolder：清洗数据输出目录
│  └─ figureFolder：QC 图输出目录
├─ 指定待读取文件类型
│  └─ Capacitance / Impedance / Inductance
├─ 指定 CSV 数据结构参数
│  ├─ headerLines：跳过 WaveForms 元数据行
│  └─ expectedRowsPerFile：每个频谱文件理论点数
├─ 指定滤波与异常值检测参数
│  ├─ Hampel / moving median
│  ├─ median filter
│  ├─ Savitzky-Golay smooth
│  └─ local/global MAD outlier detection
├─ 指定物理合理性边界
│  ├─ maxAbsValue
│  └─ maxCleanedRelativeJump
├─ 指定频段划分
└─ 指定保存开关
   ├─ saveFigures
   └─ saveMat
```

## 3. 变量说明

| 变量 | 类型 | 作用 |
|---|---:|---|
| `cfg` | struct | 配置结构体，主脚本读取的所有参数都保存在这里。 |
| `cfg.targetFolder` | char | 原始实验数据所在文件夹名。当前指向 `0 45 0 45 0 编织纹复材D31 MFC-温度导致传感性能退化试验`。 |
| `cfg.outputFolder` | char | MATLAB 清洗结果输出目录，默认为 `当前工作目录/outputs/stage1_preprocessed`。 |
| `cfg.figureFolder` | char | QC 图片输出目录，默认为 `outputFolder/qc_plots`。 |
| `cfg.allowedSuffixes` | cell array | 只允许处理的 CSV 后缀类型：电容、阻抗、电感。 |
| `cfg.headerLines` | double | Digilent WaveForms CSV 前面的元数据行数。当前为 30，表示第 31 行开始是表格列名。 |
| `cfg.expectedRowsPerFile` | double | 每个频谱文件期望有 2000 个频率点，用于 QC 检查。 |
| `cfg.hampelWindow` | double | Hampel 或移动中位数异常检测窗口长度，必须是奇数更合适。 |
| `cfg.hampelSigma` | double | Hampel 阈值倍数，越大越宽松。 |
| `cfg.medianWindow` | double | 中值滤波窗口长度，用于去除尖峰噪声。 |
| `cfg.sgWindow` | double | Savitzky-Golay 平滑窗口长度，用于保留谱曲线形状的平滑。 |
| `cfg.sgOrder` | double | Savitzky-Golay 多项式阶数。 |
| `cfg.localWindow` | double | 局部 MAD 异常检测窗口长度。 |
| `cfg.localMadSigma` | double | 局部 MAD 阈值倍数。 |
| `cfg.globalMadSigma` | double | 全局 MAD 阈值倍数。 |
| `cfg.maxAbsValue` | double | 物理上不合理的极端数值上限，超过则标记为异常。 |
| `cfg.maxCleanedRelativeJump` | double | 清洗值相对原始值变化过大时，再额外标记为异常的比例阈值。 |
| `cfg.frequencyBands` | double matrix | 后续 Python 特征提取要使用的频段边界。 |
| `cfg.saveFigures` | logical | 是否保存清洗前后 QC 图片。 |
| `cfg.saveMat` | logical | 是否保存 `.mat` 格式结果。 |

## 4. 逐行说明

| 行号 | 代码/内容 | 作用 |
|---:|---|---|
| 1 | `function cfg = MFC_Preprocess_Config()` | 定义一个 MATLAB 函数，函数名与文件名一致，返回值是配置结构体 `cfg`。 |
| 2 | `% Configuration...` | 注释：说明本文件用于 MFC 原始阻抗谱预处理配置。 |
| 3 | `%` | 空注释行，用于分隔说明。 |
| 4 | `% MATLAB is...` | 注释：强调 MATLAB 是原始 CSV 预处理入口。 |
| 5 | `% Python should...` | 注释：说明 Python 只消费 MATLAB 输出的清洗数据。 |
| 6 | 空行 | 增强可读性。 |
| 7 | `cfg.targetFolder = ...` | 设置原始数据目录名。主脚本会用 `pwd + targetFolder` 定位实验文件夹。 |
| 8 | `cfg.outputFolder = fullfile(...)` | 设置清洗结果输出目录。`fullfile` 可跨平台拼接路径。 |
| 9 | `cfg.figureFolder = fullfile(...)` | 设置 QC 图片目录，位于输出目录下的 `qc_plots`。 |
| 10 | 空行 | 路径配置与文件类型配置之间的分隔。 |
| 11 | `cfg.allowedSuffixes = ...` | 设置只处理三类 CSV：`Capacitance`、`Impedance`、`Inductance`。其他 CSV 如 Phase/Voltage/Current 会被跳过。 |
| 12 | `cfg.headerLines = 30` | 指定读取 CSV 时跳过前 30 行仪器参数。 |
| 13 | `cfg.expectedRowsPerFile = 2000` | 指定每个频谱文件应有 2000 行数据，用于输出 QC 中的 `row_count_ok`。 |
| 14 | 空行 | 结构分隔。 |
| 15 | `% Filtering parameters...` | 注释：下面开始定义滤波参数，窗口最好取奇数。 |
| 16 | `cfg.hampelWindow = 11` | Hampel/移动中位数检测窗口为 11 个频率点。 |
| 17 | `cfg.hampelSigma = 3.0` | Hampel 异常判断阈值为 3 倍尺度。 |
| 18 | `cfg.medianWindow = 5` | 中值滤波窗口为 5 点。 |
| 19 | `cfg.sgWindow = 21` | Savitzky-Golay 平滑窗口为 21 点。 |
| 20 | `cfg.sgOrder = 3` | Savitzky-Golay 拟合多项式阶数为 3。 |
| 21 | 空行 | 滤波参数与异常检测参数分隔。 |
| 22 | `% Robust local...` | 注释：下面定义稳健异常点检测参数。 |
| 23 | `cfg.localWindow = 21` | 局部异常检测窗口为 21 个频率点。 |
| 24 | `cfg.localMadSigma = 6.0` | 局部 MAD 阈值为 6 倍，主要识别尖峰、突跳。 |
| 25 | `cfg.globalMadSigma = 12.0` | 全局 MAD 阈值为 12 倍，主要识别极端离群值。 |
| 26 | 空行 | 异常检测与物理边界分隔。 |
| 27 | `% Conservative physical...` | 注释：说明下面是物理合理性边界。 |
| 28 | `% some exported...` | 注释：说明感抗/电感可能为负，因此边界不能简单设为正数。 |
| 29 | `cfg.maxAbsValue = 1.0e12` | 如果数值绝对值超过 `1e12`，认为物理上极不合理并标记异常。 |
| 30 | `cfg.maxCleanedRelativeJump = 0.50` | 如果清洗后数值相对原始值变化超过 50%，额外标记，提示清洗影响较大。 |
| 31 | 空行 | 物理边界与频段配置分隔。 |
| 32 | `% Frequency bands...` | 注释：说明频段划分会被后续 Python 特征提取使用。 |
| 33 | `cfg.frequencyBands = [` | 开始定义频段矩阵。 |
| 34 | `1, 50` | 低频段：1-50 Hz。 |
| 35 | `50, 200` | 中低频段：50-200 Hz。 |
| 36 | `200, 500` | 中频段：200-500 Hz。 |
| 37 | `500, 1000` | 中高频段：500-1000 Hz。 |
| 38 | `1000, 2000` | 高频段：1000-2000 Hz。 |
| 39 | `];` | 结束频段矩阵定义。 |
| 40 | 空行 | 频段配置与保存开关分隔。 |
| 41 | `cfg.saveFigures = true` | 开启 QC 图片保存。若设为 `false`，主脚本不会调用绘图函数。 |
| 42 | `cfg.saveMat = true` | 开启 `.mat` 输出。若设为 `false`，只输出 CSV。 |
| 43 | `end` | 结束函数。 |

## 5. 调参建议

- 如果原始谱曲线很平滑但偶尔有尖峰，可适当降低 `cfg.localMadSigma`。
- 如果清洗过度、真实突变被抹掉，可提高 `cfg.localMadSigma` 或减小 `cfg.sgWindow`。
- 如果需要更强平滑，可提高 `cfg.sgWindow`，但过大会削弱局部损伤特征。
- 如果不想生成大量图片，可设置 `cfg.saveFigures = false`。

