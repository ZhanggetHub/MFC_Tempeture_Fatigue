# AGENTS.md — MFC 温度疲劳寿命预测项目交接文档

> **本文档面向**：接手本项目的下一位人员或 AI 协作代理（agents）。
> **目的**：仅凭这一份文档就能完整理解项目背景、研究计划、Stage 1 已经做了什么、Stage 1 输出了什么、Stage 2 该如何在 Stage 1 之上接续开发。
> **版本**：Stage 1 完成版（MATLAB 实现，已在 Windows 中文版 MATLAB R2022b 实测通过）
> **配套代码目录**：`matlab_stage1/`（25 个 `.m` 文件）

---

## 目录

1. [项目背景与目标](#1-项目背景与目标)
2. [实验数据与协议（重要）](#2-实验数据与协议重要)
3. [关键数据真相（重要）](#3-关键数据真相重要)
4. [损伤机制与建模思路](#4-损伤机制与建模思路)
5. [总体研究方案（5 个阶段）](#5-总体研究方案5-个阶段)
6. [阶段间数据流（关键）](#6-阶段间数据流关键)
7. [Stage 1 代码完整说明](#7-stage-1-代码完整说明)
8. [Stage 1 输出文件清单](#8-stage-1-输出文件清单)
9. [使用方法](#9-使用方法)
10. [Stage 2 起点与开发指南](#10-stage-2-起点与开发指南)
11. [遗留问题与已知陷阱](#11-遗留问题与已知陷阱)

---

## 1. 项目背景与目标

### 1.1 研究对象

宏纤维压电复合材料（**Macro Fiber Composites, MFC**），具体型号信息：

- 铺层：`0/45/0/45/0` 编织
- 工作模式方向：`D31`
- 待用户确认：是否为 HT 高温版本（影响最高工作温度阈值）

### 1.2 研究目标

评估**温度疲劳循环**对 MFC 电学性能的退化影响，建立**寿命预测模型**。

### 1.3 寿命预测算法的硬性要求

寿命预测算法必须**显式考虑两类损伤机制**（用户多次强调）：

1. **机制 A — 叉指电极 (IDE) 断裂 → 局部高压击穿压电纤维**
   - 循环加热使叉指电极/基体热膨胀失配累积
   - 电极局部断裂后电场集中：$E_{loc} = V/g_{IDE} \cdot \kappa(D_{ide})$
   - 当 $E_{loc}/E_{bd}(T) \geq 1$ 时压电纤维被击穿

2. **机制 B — 极化电子对失效（退极化）**
   - 热激活使极化方向受抑制 / 界面电荷注入 / 缺陷层形成
   - 直接表现为压电常数衰减、介电响应下降

### 1.4 当前数据范围与未来扩展

- **本阶段数据**：电容频谱（Cs, Cp）共 18 个 CSV
- **后续可扩展**：用户提到还有电感、阻抗等其他实验数据，等 Stage 1 框架成熟后会补进来

---

## 2. 实验数据与协议（重要）

### 2.1 数据文件清单

共 **18 个 CSV 文件**，全部由 **Digilent WaveForms Impedance Analyzer (Discovery2)** 导出：

| 文件类型 | 数量 | 内容 |
|---|---|---|
| 基线 | 1 | 未循环时的 Cs/Cp 频谱 |
| 70 °C 退化 | 3 | 第 1/2/3 次温度循环后 |
| 80 °C 退化 | 3 | 同上 |
| 90 °C 退化 | 3 | 同上 |
| 100 °C 退化 | 3 | 同上 |
| 110 °C 退化 | 3 | 同上 |
| 120 °C 退化 | 2 | 缺第 3 次（数据集不平衡点） |

**每个文件结构**：30 行 `#` 开头的头部元数据 + 数据头行 `Frequency (Hz), Trace Cs (F), Trace Cp (F)` + **2000 行**整数频率（1–2000 Hz）数据。

**注意**：基线文件的频率网格略有不同（最大约 2039 Hz、非整数节点），所有退化文件是严格 1–2000 整数 Hz。Stage 1 必须先做**频率网格对齐**才能做 ratio。

### 2.2 实验协议（**协议 A — 累计循环**）⭐

**单次温度疲劳循环 = 室温 → 加热到目标温度 → 回到室温 → 测量电学参数**

**全程使用同一片 MFC 试样**，按温度顺序累计循环。每个 CSV 对应的累计循环次数 N：

| 文件 | N（累计循环数） |
|---|---:|
| 基线 | 0 |
| 70 °C 第 1/2/3 次 | 1 / 2 / 3 |
| 80 °C 第 1/2/3 次 | 4 / 5 / 6 |
| 90 °C 第 1/2/3 次 | 7 / 8 / 9 |
| 100 °C 第 1/2/3 次 | 10 / 11 / 12 |
| 110 °C 第 1/2/3 次 | 13 / 14 / 15 |
| 120 °C 第 1/2 次 | 16 / 17 |

### 2.3 协议 A 的建模含义（Stage 3/4 必读）

**N 与 T 高度共线**（低 N → 低 T，高 N → 高 T）。
后续 Stage 3/4 必须用**热历史积分**

$$
\Theta(N, T_{\text{path}}) = \int_0^N \exp\!\left(-\frac{Q}{R\,T(\tau)}\right)\,d\tau
$$

作为合成应力变量来解耦循环数与温度的主效应。否则 ALT/Cox 等模型会无法分离 N 与 T 的边际贡献。

---

## 3. 关键数据真相（重要）

> **此节是后续所有建模决策的基础**。请新对话**务必**仔细读懂本节。
> 用户最初上传过一份 PDF 报告对数据特征做了描述，但**那份 PDF 的描述与实际 CSV 数据严重不符**。本节给出的是直接复算结果。

### 3.1 PDF 报告 vs 实际数据复算的对照

| 项 | PDF 报告原文 | 直接复算 |
|---|---|---|
| 90–110 °C 平均 Cp/基线 | 0.0048–0.0090（塌缩到 0.5–0.9 %） | **1.075–1.116（高于基线 7–12 %）** |
| Cp@100 Hz / 基线 | 0.0051–0.0157 | **1.078–1.122** |
| 谱形描述 | "突变式频谱塌缩"、"高频跌至 0.5–1.9 %" | **谱形与基线高度平行，仅整体上移；无塌缩** |

**新对话注意**：如果用户再提到 PDF 报告里的"塌缩"描述，请告知它与实际数据不符；以下 §3.2 的真实数据为准。

### 3.2 真实趋势表（频率对齐后）

| T (°C) | Cp@1 Hz | Cp@10 Hz | Cp@100 Hz | Cp@1000 Hz | stage 1→3 趋势 |
|---:|---:|---:|---:|---:|---|
| 70  | 1.066 | 1.043 | 1.036 | 1.040 | 1.040 → 1.030 → 1.026（轻微↓） |
| 80  | 1.097 | 1.069 | 1.046 | 1.054 | 非单调 |
| 90  | 1.123 | 1.092 | 1.078 | 1.083 | 1.075 → 1.078 → 1.087（缓慢↑） |
| 100 | 1.149 | 1.114 | 1.099 | 1.099 | 几乎不变 |
| 110 | 1.160 | 1.130 | 1.117 | 1.121 | 几乎不变 |
| 120 | 1.207 | 1.170 | 1.155 | 1.156 | 缺第 3 个样本 |

### 3.3 物理解读（建模指导）

1. **当前数据未进入显著疲劳损伤区**。所有 Cp/Cs 比基线**高** 3–22 %，谱形完整，无塌缩。
2. 这是**铁电压电材料典型的温度增介电效应**：T < 居里温度时 ε′ 随 T 升高单调增加，导致测量电容上升。
3. **stage→stage 单点变化极小**（多数 < 0.5 %），说明每个温度的 1/2/3 次循环之间损伤累积量级很小。
4. 频谱中的 ~50 Hz、~350 Hz 窄带 notch 是**仪器伪影**（工频 / 量程切换），所有文件包括基线都有，**不是损伤特征**。Stage 1 已自动检测并抑制。

### 3.4 对 Stage 3/4 建模的硬约束

- 模型必须能解释"温度增介电"主导的当前数据 → 损伤潜变量 $D_{ide}, D_{pol} \approx 0$ + 必须显式包含 $\varepsilon(T)$ 因子
- 必须留有"潜在不可见损伤"入口，待循环量级增大后激活
- **Stage 4 不要在当前 17 条谱上拟合任何寿命数字**，只做状态识别和退化轨迹的"零损伤"基线验证

---

## 4. 损伤机制与建模思路

### 4.1 双潜变量观测模型

引入两个潜变量：

- $D_{ide}(N, T) \in [0, 1]$ — 表征 IDE 断裂 + 局部击穿
- $D_{pol}(N, T) \in [0, 1]$ — 表征极化衰减 / 退极化

观测方程（描述损伤如何映射到电容频谱）：

$$
C_p(f, N, T) = C_{p0}(f) \cdot \varepsilon(T) \cdot \left[(1 - \alpha_p D_{pol}) + (1 - D_{ide}) + D_{ide} \cdot \frac{1}{1 + (f/f_b)^m}\right]
$$

$$
C_s(f, N, T) = C_{s0}(f) \cdot \varepsilon(T) \cdot \left[(1 - \alpha_s D_{pol}) + 1 - \gamma_s D_{ide} \cdot \frac{(f/f_b)^m}{1 + (f/f_b)^m}\right]
$$

其中 $\varepsilon(T)$ 是热增介电因子（**解释当前数据的关键**），$f_b$ 是损伤拐点频率，$m$ 控制塌缩陡峭度。

### 4.2 损伤演化方程（含温度激活 + 累计循环）

$$
\frac{dD_{pol}}{dN} = A_{pol} (1 - D_{pol}) \exp\!\left(-\frac{Q_{pol}}{R(T+273.15)}\right)
$$

$$
\frac{dD_{ide}}{dN} = A_{ide} (1 - D_{ide}) \exp\!\left(-\frac{Q_{ide}}{R(T+273.15)}\right) \left(\frac{E_{loc}}{E_{bd}(T)}\right)^p
$$

$$
E_{loc} = \kappa(D_{ide}) \cdot \frac{V}{g_{IDE}}, \quad \kappa(D_{ide}) = \frac{1}{1 - \eta D_{ide}}
$$

### 4.3 物理约束（贯穿整个建模）

| 约束 | 数学形式 | 用于哪一阶段 |
|---|---|---|
| MFC 工作温度上限 | $T \leq 85\,°C$（标准）/ $130\,°C$（HT） | Stage 4 寿命外推 |
| 击穿场强 | $E_{loc} / E_{bd}(T) \leq 1$ | Stage 3 IDE 损伤项 |
| 线弹性应变极限 | < 1000 ppm（驱动）/ 600 ppm（采集） | Stage 4 ALT 协变量 |
| 居里温度退极化 | $D_{pol} \to 1$ 当 $T \to T_C$ | Stage 3 $D_{pol}$ 项 |
| 纤维-基体热膨胀差 | $\Delta\text{CTE} \times \Delta T$ 累积 | Stage 3 $D_{ide}$ 项 |

---

## 5. 总体研究方案（5 个阶段）

```
┌──────────────────────────────────────────────────────────────────┐
│  Stage 1  数据处理与质量保障             ← 已完成（本文档详述）    │
│  Stage 2  特征工程（80–150 维）          ← 下一步开发              │
│  Stage 3  双损伤物理-统计混合模型                                  │
│  Stage 4  寿命预测（经验/Weibull-ALT/生存/ML）                    │
│  Stage 5  集成评估、不确定性量化、可视化与报告                    │
└──────────────────────────────────────────────────────────────────┘
```

每阶段的产出物：
1. 一个独立 `.m` 模块组（可单独 import / 调用）
2. 结构化中间产物文件（CSV / JSON / MAT），下一阶段直接消费
3. 一份阶段报告（Markdown）

---

## 6. 阶段间数据流（关键）

> **新对话开发 Stage 2 时，必须严格按本节定义的接口消费 Stage 1 的输出。**

### 6.1 Stage 1 → Stage 2

**Stage 2 应当读取的输入文件**（由 Stage 1 已生成）：

| 文件 | 路径 | 内容 |
|---|---|---|
| `stage1_long_with_cycles.csv` | `outputFolder/` | tidy long-form 表，36000 行 × 12 列，**含累计循环数 cycles 列**（推荐主输入） |
| `stage1_long.csv` | `outputFolder/` | 同上，但 cycles 全为 NaN（仅在用户未启用 attachCycles 时使用） |
| `stage1_qa_report.json` | `outputFolder/` | 18 文件的逐文件 QA + 17 项硬件元数据 |

**`stage1_long_with_cycles.csv` 列定义**（Stage 2 必读）：

| 列名 | 类型 | 含义 |
|---|---|---|
| `file` | string | 原始文件名 |
| `isBaseline` | logical | 是否基线 |
| `tempC` | double | 温度（基线为 NaN） |
| `stage` | int | 退化阶段（基线为 0） |
| `cycles` | double | **累计循环数**（基线为 0，其它为 1–17） |
| `freqHz` | double | 频率（1–2000 Hz 整数） |
| `CsF` | double | 对齐到公共网格的 Cs（仅插值，未平滑） |
| `CpF` | double | 同上，Cp |
| `CsCleanF` | double | 对齐 + 离群点替换 + notch 抑制 + Savgol 平滑后 |
| `CpCleanF` | double | 同上，Cp |
| `CsRatio` | double | `CsCleanF / Cs0CleanF`（基线本身全为 1） |
| `CpRatio` | double | 同上，Cp |

**关键点**：
- Stage 2 应优先使用 `CpCleanF/CsCleanF` 做平滑特征，用 `CpF/CsF` 做需要保留高频抖动的特征（如 total variation、wavelet 高频能量）。
- `CpRatio/CsRatio` 已经做了基线归一化，可直接作为退化指数。
- 数据按 `(file, freqHz)` 排序。同一 `file` 的所有行共享相同的 `tempC`、`stage`、`cycles`。

### 6.2 Stage 2 → Stage 3

**Stage 2 应当输出**：
- `stage2_features.csv` — 特征矩阵，每行一个文件（共 18 行，**含基线**），列为各特征 + 元数据列（file、tempC、stage、cycles）
- `stage2_features_long.csv` — 长格式版本（如果需要按温度/阶段分组建模）
- `stage2_features_report.md` — 特征清单与统计

### 6.3 Stage 3 → Stage 4

**Stage 3 应当输出**：
- `stage3_damage_states.csv` — 每个文件的 $D_{ide}, D_{pol}$ 估计值 + 不确定区间
- `stage3_observation_recon.csv` — 模型重构的 $\hat{C_p}, \hat{C_s}$ 谱与残差
- `stage3_params.json` — 物理模型参数估计（$A, Q, f_b, m, \alpha, \gamma, \eta, p, T_{ref}$）

### 6.4 Stage 4 → Stage 5

**Stage 4 应当输出**：
- `stage4_life_predictions.csv` — 每个 (T, V, ε) 工况下的预测寿命 + 置信区间
- `stage4_HI_thresholds.json` — Health Index 各等级阈值（OK/WARN/SEVERE/FAIL）
- `stage4_models.mat` — 各模型的拟合对象（Weibull / Cox / RSF / XGBoost）

---

## 7. Stage 1 代码完整说明

### 7.1 文件清单（25 个 .m 文件）

按调用层级分为 5 组：

```
入口层（用户直接调用）
├── demo_stage1.m            演示与一键运行脚本（用户的主入口）
├── runStage1.m              端到端主函数
├── test_run.m               烟雾测试（独立验证脚本）
└── diagnose_filename.m      MATLAB 中文文件名诊断脚本

配置层
├── mfc_defaultConfig.m      预处理参数默认配置
└── mfc_defaultPlotConfig.m  绘图样式默认配置（用户可在 demo 中修改）

核心管线层
├── mfc_loadFolder.m            批量加载文件夹
├── mfc_readCapacitanceCsv.m   单文件 CSV 解析
├── mfc_preprocessPipeline.m   主预处理流水线（QA → 去噪 → 对齐 → 归一化）
├── mfc_qualityCheck.m          单谱质量检查
├── mfc_attachCycles.m          注入真实疲劳循环数
├── mfc_toTable.m               转 tidy long-form table
├── mfc_saveQaReport.m          保存 QA + 元数据 JSON
├── mfc_writeLongCsv.m          兼容 Octave 的 CSV 写出器
├── mfc_writeHumanReadable.m   "给人看"的宽格式 .xlsx/.csv 输出
├── mfc_plotSpectra.m           谱与温度效应可视化（统一绘图入口）
└── mfc_applyPlotStyle.m        绘图样式应用辅助

工具层（被核心管线调用）
├── mfc_parseFilename.m        文件名 → (layup, dir, T, stage)
├── mfc_parseHeader.m          CSV 头 → 17 项硬件元数据
├── mfc_hampelMask.m           Hampel 离群点掩码
├── mfc_detectNotches.m        仪器 notch 检测
├── mfc_suppressNotches.m      notch 局部线性插补
├── mfc_savgolSafe.m           Savitzky-Golay 平滑（带回退）
├── mfc_alignToGrid.m          频率网格插值
├── mfc_instrumentGrid.m       整数 Hz 公共网格
└── mfc_commonLogGrid.m        对数等距公共网格
```

### 7.2 调用关系树

```
demo_stage1.m
├── mfc_defaultConfig() → cfg
├── runStage1(inputFolder, outputFolder, cfg)
│   ├── mfc_loadFolder(inputFolder)
│   │   └── mfc_readCapacitanceCsv(每个 CSV)
│   │       ├── mfc_parseHeader(头部行)
│   │       └── mfc_parseFilename(文件名)
│   ├── mfc_preprocessPipeline(records, cfg)
│   │   ├── mfc_qualityCheck(每条记录)
│   │   │   ├── mfc_hampelMask
│   │   │   └── mfc_detectNotches
│   │   ├── mfc_instrumentGrid 或 mfc_commonLogGrid
│   │   ├── mfc_hampelMask（离群点替换）
│   │   ├── mfc_suppressNotches（notch 抑制）
│   │   ├── mfc_savgolSafe（平滑）
│   │   └── mfc_alignToGrid（频率对齐）
│   ├── mfc_saveQaReport(records, JSON 路径)
│   ├── mfc_toTable(records) → T
│   ├── mfc_writeLongCsv(T, CSV 路径)
│   └── mfc_writeHumanReadable(records, xlsx 路径)
├── mfc_attachCycles(out.records, mapping)         ← 注入累计循环数
├── mfc_toTable(out.records)                       ← 重新生成含 cycles 的表
├── mfc_writeLongCsv(...with_cycles.csv)
├── mfc_writeHumanReadable(...with_cycles.xlsx)
├── mfc_defaultPlotConfig() → pcfg
└── mfc_plotSpectra(out.records, out.fgrid, 'figs', pcfg)
    └── mfc_applyPlotStyle (内部多次调用)
```

### 7.3 核心数据结构 — `SpectrumRecord` struct

每条记录是一个 MATLAB struct，**全部 22 个字段如下**（Stage 2 需要直接访问这些字段时的参考）：

| 字段 | 类型 | 说明 | 由谁填充 |
|---|---|---|---|
| `file` | char | 文件名 | `mfc_readCapacitanceCsv` |
| `isBaseline` | logical | 是否基线 | `mfc_parseFilename` |
| `tempC` | double | 温度（基线为 NaN） | 同上 |
| `stage` | int | 退化阶段（基线为 0） | 同上 |
| `cycles` | double | 累计循环数（初始 NaN，由 `mfc_attachCycles` 注入；基线自动 0） | `mfc_attachCycles` |
| `layup` | char | 铺层（如 `'0-45-0-45-0'`） | `mfc_parseFilename` |
| `direction` | char | 方向（如 `'D31'`） | 同上 |
| `freqHz` | column vector | 原始频率 | `mfc_readCapacitanceCsv` |
| `CsF` | column vector | 原始 Cs | 同上 |
| `CpF` | column vector | 原始 Cp | 同上 |
| `metadata` | struct | 17 项硬件参数（见 §7.4.5） | `mfc_parseHeader` |
| `qa` | struct | QA 报告（见 §7.4.6） | `mfc_qualityCheck` |
| `freqGridHz` | column vector | 公共频率网格 | `mfc_preprocessPipeline` |
| `CpGridF` | column vector | 仅对齐到公共网格的 Cp（**不平滑**） | 同上 |
| `CsGridF` | column vector | 仅对齐到公共网格的 Cs | 同上 |
| `CpCleanF` | column vector | 对齐 + 离群点替换 + notch 抑制 + 平滑 | 同上 |
| `CsCleanF` | column vector | 同上，Cs | 同上 |
| `CpRatio` | column vector | `CpCleanF / Cp0CleanF`（基线本身全为 1） | 同上 |
| `CsRatio` | column vector | 同上，Cs | 同上 |
| `tanDeltaProxy` | column vector | $(C_s - C_p) / \sqrt{C_p \cdot C_s}$，耗散因子代理 | 同上 |

### 7.4 各脚本详细说明

#### 7.4.1 入口层

##### `demo_stage1.m` — 演示与一键运行

**功能**：用户的主入口。配置路径 → 调用 `runStage1` → 注入循环数 → 可视化。

**6 节结构**：
- 第 1 节：路径（`inputFolder` / `outputFolder`）
- 第 2 节：预处理配置 `cfg`
- 第 3 节：调用 `runStage1` 执行端到端流水线
- 第 4 节：（默认注释）注入真实疲劳循环数 + 同步更新 with_cycles 文件
- 第 5 节：绘图配置 `pcfg`
- 第 6 节：调用 `mfc_plotSpectra` 出图

**用户修改入口**：
```matlab
inputFolder  = './uploads';   % CSV 所在目录
outputFolder = './mfc_out';   % 输出目录
```

**协议 A 启用**：取消第 4 节注释（参考 §9.3）。

##### `runStage1.m` — 端到端主函数

**函数签名**：`out = runStage1(inputFolder, outputFolder, cfg)`

**6 步执行流程**：
1. 创建输出目录
2. `mfc_loadFolder` 加载所有 CSV
3. `mfc_preprocessPipeline` 完整预处理
4. `mfc_saveQaReport` 写 QA JSON
5. `mfc_toTable` + `mfc_writeLongCsv` 写 tidy CSV
6. `mfc_writeHumanReadable` 写人类可读 .xlsx
7. 控制台打印 `(T, stage) → 平均 Cp_ratio` 汇总表

**返回值**：
```matlab
out.records  % cell 数组，每元素为 SpectrumRecord struct
out.fgrid    % 公共频率网格（默认 1:2000）
out.table    % tidy long-form table（MATLAB table 或 Octave 回退 struct）
```

##### `test_run.m` — 烟雾测试

独立验证脚本，验证 18 个 CSV 全部加载成功、预处理无报错、关键统计正常。

##### `diagnose_filename.m` — 诊断脚本

用于排查 MATLAB 拿到的中文文件名编码问题（参见 §11 已知陷阱）。

#### 7.4.2 配置层

##### `mfc_defaultConfig.m` — 预处理配置

返回 `cfg` 结构体，10 个字段：

| 字段 | 默认值 | 含义 |
|---|---|---|
| `gridKind` | `'integer'` | 频率网格类型：`'integer'` / `'log'` |
| `nLogPoints` | 2000 | log 网格点数 |
| `smoothWindow` | 9 | Savitzky-Golay 窗口长度 |
| `smoothPolyorder` | 2 | Savitzky-Golay 多项式阶数 |
| `suppressNotchesFlag` | true | 是否抑制 ~50/350 Hz 仪器 notch |
| `notchHalfBwHz` | 1.5 | notch 抑制半带宽（Hz） |
| `hampelWindow` | 11 | Hampel 离群点检测窗口长度 |
| `hampelNSigmas` | 4.0 | Hampel σ 阈值 |
| `logInterpBaseline` | true | 基线插值是否在 log10 域进行 |

**关键设计决策**：基线必须 log10 域插值。基线网格非整数（含 ~2039 Hz），若线性插值会引入 ~0.3 % 高频系统偏差。

##### `mfc_defaultPlotConfig.m` — 绘图样式配置

返回 `pcfg` 结构体，关键字段：

| 字段 | 默认值 | 含义 |
|---|---|---|
| `fontName` | `'Times New Roman'` | 数字字体 |
| `fontSize` | 12 | 数字字号 |
| `labelFontSize` | 13 | 轴标签字号 |
| `titleFontSize` | 13 | 标题字号 |
| `lineWidth` | 1.6 | 数据线宽 |
| `axesLineWidth` | 1.4 | 坐标轴线宽 |
| `box` | `'off'` | 必须保持 'off' 才让下两项生效 |
| `showTopAxis` | true | 显示上轴线（无刻度） |
| `showRightAxis` | true | 显示右轴线（无刻度） |
| `tickDir` | `'in'` | 刻度方向 |
| `minorTick` | `'off'` | 副刻度 |
| `grid` | `'off'` | 主网格 |
| `minorGrid` | `'off'` | 副网格 |
| `figureSize` | `[100 100 900 600]` | 画布像素 |
| `axesPosition` | `[0.11 0.13 0.84 0.78]` | 轴占画布比例 |
| `axesPositionTopBottom` | 上下两子图位置 | 详图布局 |
| `colormapName` | `'parula'` | 配色 |
| `detailPlots` | `'first_per_temp'` | 详图选择策略 |
| `keyFreqs` | `[1, 10, 100, 1000]` | 温度效应图的关键频率 |
| `dpi` | 300 | 输出 DPI |

**用户控制点**：所有图样式只在这一个文件里改。

#### 7.4.3 核心管线层

##### `mfc_loadFolder.m`

```matlab
records = mfc_loadFolder(folder, pattern)   % 默认 pattern='*Capacitance.csv'
```

`dir` 列出 → 排序 → 逐个 `mfc_readCapacitanceCsv` → 失败的文件打印 ERROR 但不中断。返回 cell 数组。

##### `mfc_readCapacitanceCsv.m`

```matlab
rec = mfc_readCapacitanceCsv(filepath)
```

**关键技术点**：
1. **二进制读取**：`fread(fid, Inf, 'uint8=>uint8')` 读字节，避开 MATLAB/Octave 在某些版本对 UTF-8 文件名的不一致处理
2. **字节级换行查找**：手动扫描 `0x0A` 字节切分行，避免 `strsplit` 在含中文字节时触发 `regexp: invalid UTF-8`
3. **CRLF 兼容**：CR (0x0D) 统一替换为 LF (0x0A)
4. **数据头定位**：找以 `'Frequency (Hz)'` 开头的行
5. 数据用 `sscanf('%f,%f,%f')` 向量化解析

##### `mfc_parseFilename.m` ⚠️ **历史 bug 高发区**

```matlab
info = mfc_parseFilename(name)
```

**关键技术点**（已踩过 3 个坑）：
1. MATLAB 字符串是 **Unicode 码点**（每个 char 一个码元）。早期错误地用 `uint8(name)` 截断 → CJK 字符被截成低字节 → 全部匹配失败。
2. 正确做法：用 MATLAB 原生 `strfind` + `char([Unicode 码点])` 构造关键词：
   ```matlab
   KW_WEAVE    = char([32534, 32455]);   % 编织
   KW_BASELINE = char([22522, 32447]);   % 基线
   KW_DUDI     = char([24230, 31532]);   % 度第
   KW_CIHUA    = char([27425, 36864, 21270]);  % 次退化
   ```
3. 不能用 `regexp(name, 'D\d{2}')` —— 因为 name 含中文字节时 Octave 会触发 UTF-8 校验。改用字节级查找：
   ```matlab
   for k = 1:numel(bytes)-2
       if bytes(k)=='D' && '0'<=bytes(k+1)<='9' && '0'<=bytes(k+2)<='9'
           info.direction = char(bytes(k:k+2)); break;
       end
   end
   ```

返回 `info = {isBaseline, tempC, stage, layup, direction}`。

**已实测在 Windows 中文版 MATLAB R2022b 通过**。

##### `mfc_parseHeader.m`

解析 `#` 开头的元数据行，提取 17 项硬件参数：
`deviceName, serialNumber, dateTime, fStartHz, fStopHz, fSteps, resistorOhm, average, probeResistanceOhm, probeCapacitanceF, compensation, wavegenAmplitudeV, wavegenOffsetV, wavegenAmplification, settleS, minPeriods, scale`。

**`wavegenAmplitudeV`** 是激励电压幅值，会进入 Stage 4 ALT 协变量（极化损伤项的电场驱动）。

##### `mfc_qualityCheck.m`

返回 `qa` 结构体（11 个字段）：
`nPoints, nNan, nInf, nNegative, nOutliersCp, nOutliersCs, notchFrequenciesHz, cpDynamicRangeDb, csDynamicRangeDb, fMinHz, fMaxHz, monotonicFreq, duplicateFreqCount, warnings`。

##### `mfc_hampelMask.m`

```matlab
mask = mfc_hampelMask(x, window, nSigmas)   % 默认 11, 4.0
```

滑动窗口内 median + MAD（×1.4826），偏差超阈则标记为 true。**Octave 兼容**：用 `win(~isnan(win))` 手动剔除 NaN。

##### `mfc_detectNotches.m`

```matlab
notches = mfc_detectNotches(freq, signal, prominenceDb)   % 默认 6 dB
```

`log10(|signal|)` 与 15 点滑动中位数差 > prominenceDb 且持续 1–5 个采样点 → 视为 notch。**回退**：无 `medfilt1` 时用内部 `local_movmedian`。

##### `mfc_suppressNotches.m`

```matlab
y2 = mfc_suppressNotches(freq, y, notchFreqs, halfBwHz)   % 默认 1.5 Hz
```

每个 notch 中心 ± halfBwHz 内做线性插补。

##### `mfc_savgolSafe.m`

```matlab
y2 = mfc_savgolSafe(y, windowLength, polyorder)
```

自动奇数化、保证 polyorder<window、信号过短时跳过。优先用 `sgolayfilt`，无 Signal Processing Toolbox 时回退到 `movmean`。

##### `mfc_alignToGrid.m`

```matlab
out = mfc_alignToGrid(fSrc, ySrc, fTarget, logY)
```

`logY=true` 时在 log10(y) 域做 `interp1` 线性插值，再 `10.^` 还原。

##### `mfc_instrumentGrid.m` / `mfc_commonLogGrid.m`

- `instrumentGrid(records)` → `(ceil(max fmin) : floor(min fmax))'`，整数 Hz
- `commonLogGrid(records, n)` → `logspace(log10(fmin), log10(fmax), n)'`

##### `mfc_preprocessPipeline.m` ⭐ **核心**

```matlab
[records, fgrid] = mfc_preprocessPipeline(records, cfg)
```

**5 步执行**：
1. QA：每条记录 `mfc_qualityCheck`
2. 找基线（无基线则报错）
3. 建公共频率网格
4. 处理基线：QA → 内部 `localCleanRaw`（Hampel + 局部插值） → notch 抑制 → 平滑 → log10 域对齐到 fgrid
5. 处理每条退化谱：同基线流程，但保留**两份**：
   - `CpGridF`（仅对齐，不平滑）— 给 Stage 2 计算变差/小波等保留抖动
   - `CpCleanF`（对齐 + 平滑 + 去 notch）— 给损伤模型用
   - `CpRatio = CpCleanF ./ Cp0Grid`
   - `tanDeltaProxy = (Cs−Cp)/√(Cp·Cs)`

##### `mfc_attachCycles.m`

```matlab
records = mfc_attachCycles(records, mapping)
```

**输入格式**：`containers.Map`，键 = `'温度_阶段'` 字符串，值 = 累计循环数。基线自动设 0。

##### `mfc_toTable.m`

```matlab
T = mfc_toTable(records)
```

输出 12 列 tidy table（见 §6.1）。

**关键 bug 修复点**：用 `exist('OCTAVE_VERSION', 'builtin') ~= 0` 检测环境，**不要**用 `exist('table', ...)`（MATLAB 中 table 是 class，返回 8，不是 5/2）。

##### `mfc_saveQaReport.m`

```matlab
mfc_saveQaReport(records, jsonPath)
```

输出 JSON 数组，每元素含 file/isBaseline/tempC/stage/cycles/layup/direction/qa/metadata。

##### `mfc_writeLongCsv.m`

兼容 MATLAB table 与 Octave struct，前者用 `writetable`，后者手动逐字段、逐行写。

##### `mfc_writeHumanReadable.m` ⭐ **新增**

```matlab
mfc_writeHumanReadable(records, outPath, mode)
```

**目的**：输出"给人看"的宽格式表，**不参与 Stage 2 特征提取**。

**3 种模式**：
- `'multi_sheet'`（默认 .xlsx）— 每文件一 sheet，sheet 名为 `Baseline`、`70C_stage1`...
- `'single_sheet'`（.xlsx）— 全部叠在一个 sheet 里
- `'single_csv'`（默认 .csv）— 全部叠在一个 csv 里

**排列顺序**：基线 → 70°C s1 → 70°C s2 → 70°C s3 → 80°C s1 → ... → 120°C s2

**每个小表的内容**：
1. 元数据头部 7 行（Label / File / Temp / Stage / Cumulative N / QA warnings / Detected notches）
2. 一行空行
3. 列名：`freqHz | Cs(F) | Cp(F) | Cs_clean(F) | Cp_clean(F) | Cs_ratio | Cp_ratio`
4. 2000 行数据
5. 一行空行后接下一张小表

##### `mfc_plotSpectra.m` ⭐ **统一绘图入口**

```matlab
mfc_plotSpectra(records, fgrid, outFolder, pcfg)
```

**生成图列表**：

| 文件 | 内容 |
|---|---|
| `fig01_Cp_spectrum.png` | Cp 绝对谱（基线 + 各温度） |
| `fig02_Cp_ratio.png` | Cp / 基线 |
| `fig03_Cs_spectrum.png` | Cs 绝对谱 |
| `fig04_Cs_ratio.png` | Cs / 基线 |
| `fig05_temp_effect_Cp.png` | Cp 在 1/10/100/1000 Hz 的温度效应 |
| `fig06_temp_effect_Cs.png` | 同上，Cs |
| `fig07_tandelta_proxy.png` | tan δ 代理 |
| `fig_detail_T*_s*.png` | 单条记录详图（按 `pcfg.detailPlots` 配置） |

**所有 figure 创建、轴位置、字体、保存逻辑都集中在本文件**，方便统一调样式。

##### `mfc_applyPlotStyle.m` ⭐ **样式应用**

```matlab
mfc_applyPlotStyle(ax, pcfg, axesPos)
```

**做的事**：
1. 字体、字号、轴线宽、刻度方向、刻度长度
2. Box=on/off 控制
3. **手动画上/右两条边框线**（在 box='off' 时通过 `line()` 在 `xlim/ylim` 上界画无刻度的线 — 这是实现"上/右轴线显示但无刻度"的关键技巧）
4. 关闭主/副网格、关闭副刻度

**注意**：必须在所有 `plot/legend/title` 之后调用，因为它会读取并锁定当前 xlim/ylim。

---

## 8. Stage 1 输出文件清单

执行完毕后 `outputFolder` 下生成：

| 文件 | 用途 | 给谁用 |
|---|---|---|
| `stage1_long.csv` | tidy long-form 表（不含 cycles 或 cycles 全为 NaN） | Stage 2 / 3 / 4 |
| `stage1_long_with_cycles.csv` | 同上，**含累计循环数** | **Stage 2/3/4 主输入** |
| `stage1_qa_report.json` | QA + 17 项元数据 | 调试 / 追溯 |
| `stage1_human_readable.xlsx` | 18 张子表，按基线 → 70°C s1 → … 顺序 | **用户人工查看** |
| `stage1_human_readable_with_cycles.xlsx` | 同上，含累计循环数 | 用户人工查看 |
| `figs/fig01_Cp_spectrum.png` 等 | 7 张主图 + N 张详图 | 用户人工查看 |

**控制台关键输出**（验证流水线正常）：

```
T(°C)  stage   Cp_ratio   Cs_ratio
70      1      1.0403     1.0410
70      2      1.0299     1.0318
70      3      1.0259     1.0347
80      1      1.0535     1.0542
...
120     1      1.1439     1.1438
120     2      1.1598     1.1597
```

数值已与 Python 参考实现交叉验证，差异 < 0.0001。

---

## 9. 使用方法

### 9.1 准备

1. 把 `matlab_stage1` 文件夹完整放到工作区
2. 把 18 个 CSV 放到一个文件夹（路径**可以**含中文，已在 R2022b Windows 中文版实测）
3. 确认 MATLAB ≥ R2020a

### 9.2 一键运行（无循环数）

修改 `demo_stage1.m` 第 1 节的 `inputFolder` / `outputFolder`，然后：
```matlab
cd('matlab_stage1')
addpath(pwd)
demo_stage1
```

### 9.3 注入真实循环数（协议 A）

打开 `demo_stage1.m`，**取消第 4 节注释**：

```matlab
mapping = containers.Map();
mapping('70_1')  = 1;   mapping('70_2')  = 2;   mapping('70_3')  = 3;
mapping('80_1')  = 4;   mapping('80_2')  = 5;   mapping('80_3')  = 6;
mapping('90_1')  = 7;   mapping('90_2')  = 8;   mapping('90_3')  = 9;
mapping('100_1') = 10;  mapping('100_2') = 11;  mapping('100_3') = 12;
mapping('110_1') = 13;  mapping('110_2') = 14;  mapping('110_3') = 15;
mapping('120_1') = 16;  mapping('120_2') = 17;
out.records = mfc_attachCycles(out.records, mapping);
out.table   = mfc_toTable(out.records);
mfc_writeLongCsv(out.table, fullfile(outputFolder, 'stage1_long_with_cycles.csv'));
mfc_writeHumanReadable(out.records, ...
    fullfile(outputFolder, 'stage1_human_readable_with_cycles.xlsx'), 'multi_sheet');
```

### 9.4 编程式调用

```matlab
addpath('matlab_stage1');
cfg  = mfc_defaultConfig();
out  = runStage1('input/folder', 'output/folder', cfg);
records = out.records;   % cell 数组，22 字段 struct
fgrid   = out.fgrid;     % 1:2000 Hz
T       = out.table;     % tidy long-form
```

### 9.5 改样式

只改 `mfc_defaultPlotConfig.m` 一个文件就够了。常用：
```matlab
pcfg.fontName        = 'Times New Roman';
pcfg.axesLineWidth   = 2.0;
pcfg.box             = 'off';
pcfg.showTopAxis     = true;
pcfg.showRightAxis   = true;
pcfg.minorTick       = 'off';
pcfg.grid            = 'off';
pcfg.axesPosition    = [0.11 0.13 0.84 0.78];   % 宽 84% 高 78%
pcfg.detailPlots     = 'first_per_temp';        % 'none'/'all'/'first_per_temp'/{[T S]...}
```

---

## 10. Stage 2 起点与开发指南

### 10.1 Stage 2 应当做什么

把 18 个文件的 2000 频点谱**压缩成每个文件 80–150 维的特征向量**，作为 Stage 3/4 的统一输入。

### 10.2 推荐特征族

| 族 | 维数估计 | 内容 | 主要回答的物理问题 |
|---|---|---|---|
| **统计** | 20–30 | 分频带均值/中位/标准差/CV、log 域斜率/曲率、Hjorth 三参数、偏度峰度 | 整体水平 |
| **频域结构** | 10–20 | fc50 / fc10、低频平台、高频尾部斜率、谱质心、谱熵 | 谱形状 |
| **形状相似度** | 5–10 | 与基线的 cosine、Pearson、DTW、Fréchet | 整体偏离 |
| **小波** | 15–25 | 3–5 级 db4/sym8 多尺度能量、子带熵、TEO、SWT | 局部不规则性 |
| **等效电路代理** | 5–10 | 一阶 RC 拟合 → C0、Rp、τ、tan δ@100Hz、Cole-Cole α | 等效电路参数 |
| **IDE 损伤代理** ⭐ | 3–5 | $K_{Cp} = C_p@10\text{Hz} / C_p@1000\text{Hz}$、Cp 高频跌幅斜率 | **机制 A 直接代理** |
| **极化损伤代理** ⭐ | 3–5 | 低频 Cs 漂移、tan δ 增量、Curie–Weiss 残差 | **机制 B 直接代理** |
| **Cp/Cs 分裂特征** | 5–10 | $\tan\delta_{proxy}$ 的统计、low-freq vs high-freq 分裂 | 机制 A vs B 分离 |

### 10.3 Stage 2 推荐的代码结构

```
matlab_stage2/
├── runStage2.m                         主入口
├── mfc_extractAllFeatures.m            遍历所有 records 生成 NxD 矩阵
├── mfc_features_statistical.m          统计族
├── mfc_features_spectral.m             频域结构族
├── mfc_features_shape.m                形状相似度族
├── mfc_features_wavelet.m              小波族
├── mfc_features_equivalent_circuit.m   等效电路族
├── mfc_features_damage_proxy.m         IDE/极化损伤代理 ⭐
├── mfc_writeFeatureTable.m             输出特征 CSV
└── demo_stage2.m                       演示脚本
```

### 10.4 Stage 2 开发的几个硬要求

1. **必须读 Stage 1 输出**：从 `stage1_long_with_cycles.csv` 加载，重建 records 结构（或直接读 records）。提供两种方式：
   - 方式 A：直接接受 Stage 1 的 `out.records` cell 数组（在 demo 里串起来）
   - 方式 B：从 `stage1_long_with_cycles.csv` 反构 records（Stage 2 独立运行）

2. **特征命名规范**：`{family}_{which}_{detail}`，如 `stat_Cp_logslope`、`damage_Kratio_Cp`、`wavelet_Cs_db4_lvl3_energy`。

3. **基线行也要算特征**：不要跳过 `isBaseline=true` 的行，因为 Stage 3 的 $\varepsilon(T)$ 拟合需要基线作为参考。

4. **输出宽格式**：每个文件一行（共 18 行），列为元数据 + 特征。元数据列固定在前 5 列：`file, tempC, stage, cycles, isBaseline`。

5. **机制 A/B 损伤代理特征是必须的**（用户多次强调）：至少要包含 `damage_ide_*`（IDE 代理）与 `damage_pol_*`（极化代理）两族，这两族是 Stage 3 的必要输入。

### 10.5 Stage 2 验证清单

| 用例 | 期望 |
|---|---|
| 18 个文件全部成功提取特征 | 特征矩阵 18 行，无 NaN（除非数据本身缺失） |
| 基线行的 ratio 类特征都在 1 附近 | 验证基线归一化逻辑 |
| 同温度的 stage 1/2/3 特征接近 | 验证当前数据"未进入显著损伤区"的事实 |
| Spearman(cycles, HI) 单调 | 验证累计循环排序合理 |
| 特征命名无重复、无非法字符 | CSV 列名合规 |

### 10.6 Stage 2 可借用的开源工具

- **Python（如果接 Python 端）**：`tsfresh`、`tsfel`、`PyWavelets`、`pyimpspec`、`impedance.py`
- **MATLAB**：Wavelet Toolbox（`cwt`、`wavedec`、`swt`）、Signal Processing Toolbox、Curve Fitting Toolbox

---

## 11. 遗留问题与已知陷阱

### 11.1 待用户确认（Stage 4 需要）

1. **样品是否为 HT 高温版**？标准版 T_max ≤ 85 °C → 90/100/110/120 °C 数据全部位于过应力区；HT 版 T_max ≤ 130 °C → 全部数据在工作区内。
2. **70 °C 第 2 次退化的 1 Hz 异常点** 已被 Hampel 滤波局部抑制，不影响后续分析。

### 11.2 已踩过的坑（新对话务必规避）

#### 坑 1：MATLAB 字符串不能用 `uint8(name)` 截断处理 CJK
- **错误做法**：`bytes = uint8(name); ...` 然后做字节匹配
- **正确做法**：`KW = char([Unicode 码点]); strfind(name, KW)`
- **症状**：所有中文文件名解析失败 → `tempC=NaN, stage=-1`

#### 坑 2：MATLAB 的 `regexp` 在含中文字节字符串上会触发 UTF-8 校验报错
- **错误做法**：`regexp(name_with_cn, 'D\d{2}', 'match')`
- **正确做法**：字节级 ASCII 查找
- **症状**：`regexp: invalid UTF-8` 错误

#### 坑 3：`exist('table', ...)` 不能用来检测 MATLAB 中 table 是否可用
- **错误做法**：`exist('table', 'builtin') == 5 || exist('table', 'file') == 2`
- **原因**：MATLAB 中 table 是 class（返回 8），既不是 builtin（5）也不是 file（2）
- **正确做法**：`isOctave = exist('OCTAVE_VERSION', 'builtin') ~= 0; haveTable = ~isOctave;`
- **症状**：MATLAB 误走入 Octave fallback 分支 → 数组索引报错

#### 坑 4：Octave 不支持 `char([>255 的码点])`
- **影响**：`mfc_parseFilename.m` 在 Octave 上无法识别中文文件
- **应对**：本项目的 Octave 兼容只覆盖**计算逻辑**，不覆盖中文文件名解析。Octave 上要测试中文文件解析必须用直接构造的字节流。
- **MATLAB 不受影响**。

#### 坑 5：Octave 旧版 `median(x, 'omitnan')` 不支持
- **应对**：手动 `x(~isnan(x))` 后再 median

#### 坑 6：CSV 元数据头里的 `Amplitude` 字段顺序
- 头部里 `Amplitude` 出现两次（Wavegen 与 Channel）。`mfc_parseHeader` 只在 `wavegenAmplitudeV` 还是 NaN 时填充，确保拿到的是 Wavegen 的振幅而不是通道振幅。

### 11.3 性能注意事项

- 18 个 CSV × 2000 频点 = 36000 行长表，处理耗时 < 5 秒
- 如果数据扩展到 100+ CSV，`mfc_hampelMask` 是性能瓶颈（双层循环），可改向量化版

### 11.4 Stage 1 不输出但 Stage 2 可能需要的派生量

如果 Stage 2 需要更多基础派生量（避免每个特征文件都重算），可以在 Stage 1 末尾加入：
- 完整的 `D = Cs_ratio - Cp_ratio` 频谱（耗散因子衰减代理）
- 基线插值后的相对介电常数 $\varepsilon(f) = C \cdot d / (\varepsilon_0 \cdot A)$（需要几何参数 d, A）

但当前不建议加，避免污染 Stage 1 的纯净度。让 Stage 2 自己算。

---

## 附录 A — 协议 A 累计循环数对应表（粘贴可用）

```matlab
mapping = containers.Map();
mapping('70_1')  = 1;   mapping('70_2')  = 2;   mapping('70_3')  = 3;
mapping('80_1')  = 4;   mapping('80_2')  = 5;   mapping('80_3')  = 6;
mapping('90_1')  = 7;   mapping('90_2')  = 8;   mapping('90_3')  = 9;
mapping('100_1') = 10;  mapping('100_2') = 11;  mapping('100_3') = 12;
mapping('110_1') = 13;  mapping('110_2') = 14;  mapping('110_3') = 15;
mapping('120_1') = 16;  mapping('120_2') = 17;
% 基线自动 cycles=0
```

## 附录 B — 兼容性矩阵

| 环境 | Stage 1 完整流水线 | 中文文件名解析 | 绘图 | xlsx 输出 |
|---|---|---|---|---|
| MATLAB R2022b Windows 中文版 | ✓ 实测通过 | ✓ | ✓ | ✓ |
| MATLAB R2020a+ Linux/macOS | ✓ 预期通过 | ✓ | ✓ | ✓ |
| MATLAB R2013b–R2019b | 大部分通过 | 需测试 | ✓ | ✓ |
| Octave 8.4 | 计算逻辑通过 | ✗ char([>255]) 限制 | gnuplot 后端有限制 | ✗ 无 xlsx 写出 |

## 附录 C — Stage 1 完整文件清单

```
matlab_stage1/
├── demo_stage1.m                  入口
├── runStage1.m                    端到端
├── test_run.m                     烟雾测试
├── diagnose_filename.m            诊断脚本
│
├── mfc_defaultConfig.m            预处理配置
├── mfc_defaultPlotConfig.m        绘图样式配置
│
├── mfc_loadFolder.m               批量加载
├── mfc_readCapacitanceCsv.m       单文件 CSV 解析
├── mfc_parseFilename.m            文件名解析（CJK-safe）
├── mfc_parseHeader.m              17 项硬件元数据
├── mfc_qualityCheck.m             单谱 QA
├── mfc_hampelMask.m               Hampel 离群点
├── mfc_detectNotches.m            notch 检测
├── mfc_suppressNotches.m          notch 抑制
├── mfc_savgolSafe.m               Savgol 平滑
├── mfc_alignToGrid.m              频率插值
├── mfc_instrumentGrid.m           整数 Hz 网格
├── mfc_commonLogGrid.m            log 网格
├── mfc_preprocessPipeline.m       主预处理流水线
├── mfc_attachCycles.m             注入循环数
├── mfc_toTable.m                  tidy long table
├── mfc_writeLongCsv.m             CSV 写出
├── mfc_writeHumanReadable.m       人类可读宽表 .xlsx/.csv
├── mfc_saveQaReport.m             QA JSON 写出
├── mfc_plotSpectra.m              统一绘图入口
└── mfc_applyPlotStyle.m           样式应用辅助
```

---

*文档完。Stage 2 起，所有新增文档应作为本 AGENTS.md 的"Stage N 章节"追加，保持本文件的演进式可追溯性。*
