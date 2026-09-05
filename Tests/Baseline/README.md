# Swift 编码器回归基线

## 来源与生成环境

- 生成提交：`6f8e34554e2967f4bed3f52d0932f39962e39913`，分支 `ui/baseline`。
- [Actions run 33936624662](https://github.com/Times1368/SSTVEncoder-iOS/actions/runs/33936624662)，基线 job `101225702714`。
- [原始 artifact 9960396981](https://github.com/Times1368/SSTVEncoder-iOS/actions/runs/33936624662/artifacts/9960396981)，名称 `sstv-baseline-6f8e34554e2967f4bed3f52d0932f39962e39913`。
- ZIP：26,803,246 bytes；SHA-256 `3a44abdbff50c416a87cfc87ce62aa11e7e3325fb7cc0765b49404a831bc1892`。下载后与 GitHub artifact digest 一致。
- Xcode **15.0.1 (15A507)**；基线日志记录选中的 `/Applications/Xcode_15.0.1.app/Contents/Developer`，完整 build version 由同次运行的 compatibility job `101225702531` 记录。
- Apple Swift **5.9**：`swiftlang-5.9.0.128.108 clang-1500.0.40.1`；target `arm64-apple-macosx14.0`；Release / `-c release`。
- Runner：`macos-14-arm64`，镜像 `20260831.0302.1`；macOS **14.8.9 (23J631)**。
- 音频：**48,000 Hz，单声道，16-bit signed little-endian PCM，RIFF WAV**；编码 Float 振幅 **0.8**。
- 输入：`coordinate-rgb-v1`，按各模式原生尺寸逐像素生成 `RGBImage`：`r=(x*8)%256; g=(y*8)%256; b=((x+y)*4)%256`；无图片读取、无缩放。

三个 WAV 都由本仓库 Swift `BaselineGenerator` 调用 **`SSTVEncoder.encode(_:mode:progress:)` → `WAVEncoder.encode`** 产出。Python 只负责启动 Swift 二进制、校验 WAV 和计算哈希，没有 Python SSTV 参考编码器。本机 Windows 未执行 Swift 或 Xcode。

本目录音频、SHA256SUMS、元数据和行序 JSON 均从上述原始 artifact 逐字节复制；没有重跑、重编码或改写原始报告。

## 哈希与实际时长

| WAV | SHA-256 | PCM 样本数 | 样本数 / 48,000（秒） | 尺寸 |
|---|---|---:|---:|---|
| Robot-36-Color.wav | `2acfaaab8b5dd14b17f283f1d4b05815259e1eb60ff461d69fe33ae3d14fa3fb` | 1,771,680 | 36.910000000 | 320×240 |
| Martin-M1.wav | `c8d217e84aeb81c83a76d00b83b4791fd3b9f370d65112d280e2c29c5c6c6251` | 5,529,608 | 115.200166667 | 320×256 |
| PD-120.wav | `8553fc7fb48ac291245df7f9bbd79bf210cb209a39115ce04dd2416ab0dc5e52` | 6,096,626 | 127.013041667 | 640×496 |

三个 WAV 合计 **26,795,960 bytes**。本机重新核验每个 WAV 的 RIFF/PCM 格式、数据长度、样本数以及哈希，均与 SHA256SUMS 和 baseline-metadata.json 一致；CI 的 `shasum -a 256 -c SHA256SUMS` 也三项通过。

### 与 SSTVMode.totalDuration 核对

这里按生成提交中未经改动的 Swift 时序表达式做只读数值核对，不是 Windows 上执行 Swift，不新增 UI 时长表。

| 模式 | 源码 totalDuration（秒） | 与 WAV 的差异 |
|---|---:|---:|
| Robot 36 | `0.910 + 240 * 0.150 = 36.910000` | 0 样本 |
| Martin M1 | `0.910 + 256 * (0.004862 + 0.000572 + 3 * (0.146432 + 0.000572)) = 115.200176` | 约 -0.448 样本 |
| PD 120 | `0.910 + 248 * (0.020 + 0.00208 + 4 * 0.121600) = 127.013040` | 约 +0.080 样本 |

三项差异均低于一个样本，远低于 1%。WAV 包含 **0.910 秒引导段**；图片本体分别为 36、114.290176、126.103040 秒，因此不能用“36 / 114 / 126 秒”的粗略值替代 totalDuration 校验。

## 原失败原因与独立行序诊断

失败步骤：`Require a complete, consistent codec-only row-order result`。编码、WAV 校验、SHA-256 与上传已成功，随后诊断脚本输出以下原文并退出 1：

```text
Separate row-order diagnostic needs review; WAV hashes remain valid:
```

| 模式 | 完成行数 | 正序平均误差 | 倒序平均误差 | 原始报告 |
|---|---:|---:|---:|---|
| Robot 36 | 240/240 | 51.0637109375 | 73.2773741319 | inconclusive |
| Martin M1 | 256/256 | 7.4369099935 | 73.5861124674 | consistent |
| PD 120 | 496/496 | 73.9222572245 | 81.3704322077 | inconclusive |

诊断器要求最佳平均误差小于 48，并比另一方向至少好 5；Robot/PD 没有达到第一条，不能据此断定发生上下翻转。**Martin M1 自环行序已验证，无需处理；Robot 36 / PD 120 未定，需要单独诊断。** 没有任何报告判为 reversed，本次不冒称“全部自洽”，也不创建已确诊的“发射方向错误” issue。

这条诊断只走 RGBImage → Swift 编码器 → Swift 解码器，未覆盖 App 的 PNG/UIKit 图片载入器；本轮不修改载入器或任何 DSP。诊断改为仅报告、不影响基线退出码，原始结果保留不改。

## 复用与比较规则

1. 保留本目录三个原始 WAV 和 SHA256SUMS，不随重新构建覆盖。
2. 比较时用相同生成提交对应的坐标输入规则、采样率、振幅及 Xcode/Swift 环境运行 Swift 编码器。
3. 对新 WAV 执行 SHA-256 与此基线逐一比较。若环境不同，先单独记录新环境与差异，不能直接把哈希变化归因于算法。
4. `baseline-metadata.json` 还记录了原始核心 Swift 源文件的 SHA-256，可进一步区分源码变化与工具链变化。
