# MFC_QC_Plots.m 中文说明

`MFC_QC_Plots.m` 是 Stage 1 的质量控制绘图函数。

详细说明已统一整理到：

- [更新后 Stage 1 全电学参数预处理说明](docs/README_Stage1_Updated_CN.md)

## 函数签名

```matlab
MFC_QC_Plots(freq, alignedValue, cleanValue, isOutlier, ...
    isDistortion, isNotchArtifact, sourceFile, metric, channel, outPath)
```

## 输入变量

| 变量 | 作用 |
|---|---|
| `freq` | 公共频率网格，单位 Hz |
| `alignedValue` | 对齐到公共频率网格后的原始谱值 |
| `cleanValue` | 清洗后的谱值 |
| `isOutlier` | 孤立异常点标记 |
| `isDistortion` | 非物理畸变点标记 |
| `isNotchArtifact` | 仪器 notch 伪影标记 |
| `sourceFile` | 原始 CSV 文件名 |
| `metric` | 电学参数类型 |
| `channel` | 通道名 |
| `outPath` | PNG 输出路径 |

## 输出

函数没有 MATLAB 返回值，实际输出是一张 PNG 图。

图中包含：

- 灰线：`alignedValue`
- 红线：`cleanValue`
- 蓝点：`isOutlier`
- 橙点：`isDistortion`
- 绿点：`isNotchArtifact`
- 下方子图：`cleanValue - alignedValue`

## 物理检查意义

这张图用于人工确认清洗是否合理。尤其要检查谐振/反谐振附近的连续峰谷是否被保留，以及仪器 notch 是否被标记但没有误伤大段真实谱形。
