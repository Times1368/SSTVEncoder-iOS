# UI 改造执行记录

本分支从 `main` 的 `6ab8a20cd44403f2e5fef12ac9def3d9a867c236` 创建，不继承 `ui/baseline`。

## 当前范围

1. Theme + Any/Dark 颜色资产 + 通用组件。
2. 接收 / 发射 / 图库 / 设置四 Tab，接收默认；所有导航栏 inline。保留现有收发页面与退出清理，图库、设置先提供明确标注的骨架，不伪装成已具备存储或偏好设置。

两步分开 commit，一起推 `ui/design-system`。Windows 只做静态/Python 检查；Swift/Xcode 交给 Actions，推送后立即报告链接，不等待、不自动合主干。

## 已确认的实现边界

- 不修改 SSTVKit、SSTVFrameAssembler、图像处理、PCM、麦克风 tap、收发 ViewModel 或 PlaybackController。
- iOS 17 原生 API 直接用；允许 ContentUnavailableView / @Observable，但不批量改写 ObservableObject；仍禁止 SwiftData 和第三方库。
- 后续编码进度接现有回调；完成时长读 PCMBuffer.duration，未完成预估读 SSTVMode.totalDuration。
- 后续逐行落图用 append 返回的 completedRows，UI 限制到 15 fps；不新增解码接口。
- 后续电平与 FFT 在同一个 AsyncStream 消费循环里取同批样本，不改 tap。
- 后续连续接收在 App 消费循环重置 decoder，保持麦克风与最近图像；HF Fax 入口及行为保持独立。
- 保留原始两段隐私文案；默认显示接收页不等于自动开麦。
- 不更换用户提供的设计方向，不偷偷缩减剩余页面功能。本轮未做的图库持久化、完整发射/接收改版、瀑布和设置仍按用户确认顺序推进。

## 设计系统

18 个颜色 token 均位于 `SSTVEncoder/Resources/Theme.xcassets`，每个有 Any/Dark 配置。仪表背景始终 #060A14，accent 为 #2F6BFF / #4C86FF，信号色和彩条严格按 UI 稿。

通用组件包含 SSTVCard、PrimaryActionButton/Style、SecondaryActionStyle、StatusPill、InstrumentCanvas、ColorBars、SSTVProgressBar、ScanLineOverlay、ModeChip、SSTVEmptyState。全部只接展示值或 action 闭包，不依赖音频/DSP。数字展示采用 monospacedDigit；主按钮禁用时要求给出 disabledReason。

## 验证边界

- Python 契约测试检查 Any/Dark、色值、资产接线、源码边界与四 Tab 文案。
- 新增 ThemeTests 在 iOS 测试宿主检查实际 UIColor 资产解析和 token 尺寸；步骤 2 将增加 AppTabTests 检查顺序/默认值。执行结果以新 Actions 为准。
- 本机没有运行 Swift/Xcode，也没有把静态检查或设计稿当成 App 渲染验收。真实 iPhone、音频、电平、瀑布、连续收图等原十项验收仍未执行。
