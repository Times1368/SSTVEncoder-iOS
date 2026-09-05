# 冻结的 Swift 编码 WAV 基线

这里为接收质量分支记录既有基线的来源，不重新定义基线、不重跑旧 workflow，
也不把 Python 数值模型输出当作 Swift 结果。原始 WAV 保留在原 artifact；
本分支的 `EncoderBaselineTests` 仅生成待比较的验证副本。

## 来源与环境

- 生成 commit：`6f8e34554e2967f4bed3f52d0932f39962e39913`，分支 `ui/baseline`。
- [原 Actions run 33936624662](https://github.com/Times1368/SSTVEncoder-iOS/actions/runs/33936624662)，基线 job `101225702714`。
- [原 artifact 9960396981](https://github.com/Times1368/SSTVEncoder-iOS/actions/runs/33936624662/artifacts/9960396981)：
  `sstv-baseline-6f8e34554e2967f4bed3f52d0932f39962e39913`。
- 原 ZIP：26,803,246 bytes；SHA-256 `3a44abdbff50c416a87cfc87ce62aa11e7e3325fb7cc0765b49404a831bc1892`。
- Xcode 15.0.1（15A507）；Apple Swift 5.9，
  `swiftlang-5.9.0.128.108 clang-1500.0.40.1`，`arm64-apple-macosx14.0`，Release。
- 原 runner：macos-14-arm64，镜像 `20260831.0302.1`；macOS 14.8.9（23J631）。
- 格式：48000 Hz、单声道、16-bit signed little-endian PCM、RIFF WAV；Float 振幅 0.8。
- 输入：各模式原生尺寸的 `RGBImage`；
  `r=(x*8)%256; g=(y*8)%256; b=((x+y)*4)%256`，无图片文件读取或缩放。
- 生产路径：Swift `SSTVEncoder.encode(_:mode:progress:)` → `WAVEncoder.encode`。
  Python 仅负责旧产物的外层生成调度/格式校验/哈希，未实现或替代 SSTV 编码器。

## 冻结值

| WAV | 样本数 | duration = samples / 48000 | SHA-256 |
|---|---:|---:|---|
| Robot-36-Color.wav | 1771680 | 36.910000000 s | `2acfaaab8b5dd14b17f283f1d4b05815259e1eb60ff461d69fe33ae3d14fa3fb` |
| Martin-M1.wav | 5529608 | 115.200166667 s | `c8d217e84aeb81c83a76d00b83b4791fd3b9f370d65112d280e2c29c5c6c6251` |
| PD-120.wav | 6096626 | 127.013041667 s | `8553fc7fb48ac291245df7f9bbd79bf210cb209a39115ce04dd2416ab0dc5e52` |

包含 0.910 秒引导段。对应 `SSTVMode.totalDuration` 分别为 36.910000、
115.200176、127.013040 秒，差异均不到一个样本，不使用模式名中的数字作为时长。

## 复核规则

`SSTV_VERIFY_ENCODER_BASELINE=1` 仅用于固定的 Swift 5.9 Release CI。
验证 WAV 写入新运行的 `receive-quality-xcode15-<commit>/encoder-check/`，
实际工具链及提交写入同一产物的 `toolchain.txt`。如果哈希不同，先核对工具链、
目标架构、构建配置与输入，不更新这些冻结值来让测试通过。

旧基线 job 是在三个 WAV、哈希校验和上传之后，被独立的行序诊断阻断。
旧报告：Martin M1 为 consistent；Robot 36 / PD 120 为 inconclusive，
并未判定 reversed。它们不能证明图片载入器颠倒；本阶段不修改载入器，
也不把未定报告改写成“已验证”。
