# MFC_Preprocess_Config.m 中文说明

`MFC_Preprocess_Config.m` 是 Stage 1 全电学参数预处理的配置中心。

详细说明已统一整理到：

- [更新后 Stage 1 全电学参数预处理说明](docs/README_Stage1_Updated_CN.md)

## 本文件主要配置内容

- 输入实验文件夹：`cfg.targetFolder`
- 输出目录：`cfg.outputFolder`
- QC 图目录：`cfg.figureFolder`
- 允许处理的 8 类电学参数：`cfg.allowedSuffixes`
- 基线温度：`cfg.baselineTempC = 25`
- 公共频率网格：`cfg.commonFreqHz = (1:2000)'`
- Hampel / MAD / 中值滤波 / Savitzky-Golay 参数
- 仪器 notch 频率：`50 Hz`、`350 Hz`
- 是否输出 MAT、QC 图、人类可读 Excel

## 参数修改影响

- 增大 `cfg.localMadSigma`、`cfg.globalMadSigma`：异常判别更保守，更不容易误删真实压电响应。
- 减小 `cfg.localMadSigma`、`cfg.globalMadSigma`：异常判别更激进，可能更强地去除尖峰，但有误伤谐振/反谐振风险。
- 增大 `cfg.sgWindow`：曲线更平滑，但局部细节会减少。
- 减小 `cfg.sgWindow`：保留更多局部细节，但噪声抑制减弱。
- 修改 `cfg.commonFreqHz`：会改变所有输出表的频率网格，也会影响 `ratioToBaseline` 的逐点计算。
