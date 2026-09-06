# UI 改造执行记录

> 本文保留 `ui/design-system` 阶段的范围和验证历史，不是最新总进度。
> 当前状态与协作要求见 [PROJECT_HANDOFF.zh-CN.md](PROJECT_HANDOFF.zh-CN.md)。
> 截至 2026-09-06，后续接收质量/中途接收提交 `10cc147` 已通过四项 CI；
> 用户已授权整合 main。下文“不自动合主干”“不改 Core/DSP”描述的是当时 UI 阶段，
> 不表示后续获批的接收修复不存在。未来 UI 工作仍不得顺带修改 DSP。

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
- 新增 ThemeTests 在 iOS 测试宿主检查实际 UIColor 资产解析和 token 尺寸；AppTabTests 检查顺序/默认值。执行结果以新 Actions 为准。
- 本机没有运行 Swift/Xcode，也没有把静态检查或设计稿当成 App 渲染验收。真实 iPhone、音频、电平、瀑布、连续收图等原十项验收仍未执行。

## 颜色资产打包修复（2026-09-05）

- 失败证据：[Actions #12 / iOS 17 测试 job](https://github.com/Times1368/SSTVEncoder-iOS/actions/runs/33938721941/job/101231711387)。Xcode 15.0.1 / Swift 5.9，XcodeGen 2.46.0；SwiftPM 测试通过，App 测试在 ThemeTests 失败。第一条错误是 `ThemeTests.swift:56: XCTUnwrap failed: expected non-nil value of type "UIColor"`；另一个测试的 18 个颜色 × 2 个外观断言全部失败。
- 根因不是缺少颜色文件。18 组 Any/Dark 资产已经提交，但 `project.yml` 把两个资产目录写在 target 级 `resources:`，该键不被 XcodeGen 识别。完整构建日志没有 `CompileAssetCatalog` / `actool` 步骤；App 未编译这些资源。
- 按 [XcodeGen 2.46.0 Sources 规范](https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md#sources)，将生成的 AppIcon 与 Theme 目录都移到 App target 的 `sources`，分别指定 `buildPhase: resources`。不重复创建颜色，不添加硬编码后备色，不切换测试 bundle 来绕过失败。
- 先新增配置反例测试，确认旧校验器漏掉错误层级、错误 target、缺少 Theme 和错误编译阶段；再修校验器，确认它能拒绝本次出错的原始配置；最后修项目声明。本地 Python 测试 25/25、仓库契约与 `git diff --check` 通过。现有 workflow 已执行这些脚本，无需改变 CI 流程。
- ThemeTests 保留原来的全部明暗颜色和精确色值断言，另加宿主 bundle ID 与 `Assets.car` 存在性检查。修复后的 Swift/iOS 运行结果待此次推送的 Actions 验证，不宣称已经通过。
- SSTVKit、Core、App 源码与本分支的 main 基点完全一致；颜色文件及色值未改；`ui/baseline` 未修改、未推送、未重跑。只在 `ui/design-system` 修复，不合主干、不推进后续模块。
