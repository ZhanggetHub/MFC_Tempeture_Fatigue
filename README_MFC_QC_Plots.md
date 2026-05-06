# README: MFC_QC_Plots.m

## 1. 脚本定位

`MFC_QC_Plots.m` 是 MATLAB Stage 1 预处理流程中的质量控制绘图函数。  
它不负责读取 CSV，也不负责滤波算法本身；它只接收主脚本已经准备好的：

- 频率数组 `freq`
- 原始谱值 `raw`
- 清洗后谱值 `cleaned`
- 异常点标记 `isOutlier`
- 文件名 `sourceFile`
- 通道名 `channel`
- 输出图片路径 `outPath`

然后保存一张清洗前后对比图。

## 2. 总体逻辑树

```text
MFC_QC_Plots
├─ 创建不可见 figure
├─ 建立上下两行 tiledlayout
├─ 上图：原始值 vs 清洗值
│  ├─ 灰线：raw
│  ├─ 红线：cleaned
│  └─ 蓝点：异常点位置
├─ 下图：清洗残差 cleaned - raw
│  ├─ 黑线：残差
│  └─ 蓝点：异常点残差
├─ 导出 PNG
└─ 关闭 figure，释放内存
```

## 3. 输入变量说明

| 变量 | 类型 | 作用 |
|---|---:|---|
| `freq` | numeric vector | 频率轴，单位 Hz。 |
| `raw` | numeric vector | 原始测量谱值，未清洗。 |
| `cleaned` | numeric vector | 清洗后的谱值。 |
| `isOutlier` | logical vector | 与 `freq/raw/cleaned` 同长度，`true` 表示该点被识别为异常点。 |
| `sourceFile` | char/string | 原始 CSV 文件名，用作图标题。 |
| `channel` | char/string | 当前绘制的通道名，如 `Trace Cs (F)`、`Trace |Z| (Ohm)`。 |
| `outPath` | char/string | PNG 图片保存路径。 |

## 4. 输出结果

函数没有 MATLAB 返回值。  
它的实际输出是一个 PNG 文件：

```text
outputs/stage1_preprocessed/qc_plots/*.png
```

该图片用于检查：

- 原始曲线是否存在尖峰。
- 清洗曲线是否过度平滑。
- 异常点位置是否合理。
- 清洗残差是否集中在异常点附近。

## 5. 逐行说明

| 行号 | 代码/内容 | 作用 |
|---:|---|---|
| 1 | `function MFC_QC_Plots(...)` | 定义 QC 绘图函数，输入为频率、原始值、清洗值、异常标记和输出路径。 |
| 2 | `% Save a compact...` | 注释：说明本函数保存单个通道的清洗前后对比图。 |
| 3 | 空行 | 提高可读性。 |
| 4 | `fig = figure(...)` | 创建图窗。`Visible='off'` 表示后台绘图，不弹出窗口；`Color='w'` 设置白底；`Position` 设置图像尺寸。 |
| 5 | `tiledlayout(2, 1, ...)` | 创建 2 行 1 列布局。上图放原始/清洗曲线，下图放残差曲线。 |
| 6 | 空行 | 布局定义与第一幅子图分隔。 |
| 7 | `nexttile;` | 切换到第一块子图区域。 |
| 8 | `plot(freq, raw, ...)` | 绘制原始数据曲线，灰色细线；`hold on` 允许继续叠加曲线。 |
| 9 | `plot(freq, cleaned, ...)` | 绘制清洗后数据曲线，红色较粗线。 |
| 10 | `if any(isOutlier)` | 判断是否存在异常点。若没有异常点，则不绘制散点。 |
| 11 | `scatter(...)` | 在原始曲线上用蓝色点标出异常点。 |
| 12 | `end` | 结束异常点绘制判断。 |
| 13 | `grid on;` | 打开网格，便于观察频率位置和数值变化。 |
| 14 | `xlabel('Frequency (Hz)')` | 设置横轴标签为频率。 |
| 15 | `ylabel(channel, 'Interpreter', 'none')` | 设置纵轴标签为通道名；关闭解释器，避免 `|Z|` 等符号被误解析。 |
| 16 | `title(sourceFile, 'Interpreter', 'none')` | 图标题使用源文件名；关闭解释器，避免中文或特殊符号显示异常。 |
| 17 | `legend(...)` | 添加图例：原始曲线、清洗曲线、异常点。 |
| 18 | 空行 | 第一幅图和第二幅图分隔。 |
| 19 | `nexttile;` | 切换到第二块子图区域。 |
| 20 | `plot(freq, cleaned - raw, ...)` | 绘制清洗残差曲线，残差等于清洗值减原始值。 |
| 21 | `if any(isOutlier)` | 判断是否存在异常点。 |
| 22 | `scatter(...)` | 在残差图上标出异常点对应的残差大小。 |
| 23 | `end` | 结束异常点残差绘制判断。 |
| 24 | `grid on;` | 打开残差图网格。 |
| 25 | `xlabel('Frequency (Hz)')` | 设置残差图横轴。 |
| 26 | `ylabel('Cleaned - Raw')` | 设置残差图纵轴。 |
| 27 | `title('Cleaning residual')` | 设置残差图标题。 |
| 28 | 空行 | 绘图和导出之间分隔。 |
| 29 | `exportgraphics(...)` | 将图窗导出为 PNG，分辨率为 180 dpi；`char(outPath)` 保证路径类型兼容。 |
| 30 | `close(fig)` | 关闭图窗，释放内存，避免批量绘图时积累大量 figure。 |
| 31 | `end` | 结束函数。 |

## 6. 图像解读方法

- 如果灰线和红线基本重合，说明清洗影响很小。
- 如果只有少数蓝点被替换，通常是正常尖峰去除。
- 如果红线明显偏离灰线大范围趋势，说明滤波可能过强，应回到 `MFC_Preprocess_Config.m` 调小平滑窗口。
- 如果蓝点密集出现在某个频段，可能表示该频段测量不稳定，也可能对应局部损伤导致的阻抗谱异常。

