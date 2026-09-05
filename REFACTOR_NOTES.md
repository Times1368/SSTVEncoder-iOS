# SSTV 大改版事实与进度记录

- 勘察日期：2026-09-05
- 勘察基线：`e2419194f7602e5a99b08c9e53248d53c23bf788`
- 仓库：`Times1368/SSTVEncoder-iOS`
- 原则：`SSTVKit/Sources/SSTVKit` 是受保护的 DSP 核心；VIS、行时序、色彩转换和重采样行为不得改变。`SSTVFrameAssembler.swift` 一行不动；已有快照字段足够，不新增算法回调。

## 2026-09-05 用户确认的修订（覆盖旧任务单的冲突要求）

- iOS 17 API 直接使用，不添加低版本分支；允许 `NavigationStack`、`.presentationDetents`、`ContentUnavailableView`、`.symbolEffect`、`@Observable`。保留 SwiftData 和第三方库禁令。新状态管理沿用 `ReceiverViewModel` 风格，不批量改写现有 `ObservableObject`。
- 编码进度直接接现有 `encode(_:mode:progress:)`；已编码时长读 `PCMBuffer.duration`，未编码预估读 `SSTVMode.totalDuration`。不另算、不解析模式名、不硬编码时长表。
- `append()` 的 `SSTVDecodedFrame` 已有 `completedRows`、`totalRows`、`progress` 和 `isComplete`（`SSTVDecodeTypes.swift:91-121`）。消费真实快照，UI 限制到 15 fps，以完成行数画扫描线并遮住未收行；禁止改 assembler 或新增逐行 observer。
- 连续接收只改 App 消费循环：完整帧入库、重置 decoder、继续同一个 `AsyncStream`，不 break、不停麦；等待下一帧期间保留最近图像。
- 电平和 FFT 在同一个 `for await chunk` 中并联消费同批 `[Float]`，不是再开一个争抢样本的 AsyncStream 迭代器；不改 `MicrophoneReceiver` 的 tap 内部。
- 发射模式仅含 15 个 `SSTVMode`；HF Fax 保持 `HFFaxProfile` 与现有行为，仅在接收选择中与自动识别 SSTV 并列。
- `PlaybackController` 仍每 0.1 秒更新；扫描线在 UI 做 0.1 秒线性插值，位置跳过现有引导段。
- 原样保留两段隐私文案；麦克风仅由用户点击启动；UI 全简体中文。原 UI 稿的布局、持久化、告警和十项验收继续有效。
- 唯一写仓库执行体为主代理，不启动子代理。Windows 不执行 Swift/Xcode；命令非交互且不超过 120 秒。
- 每块推到 `ui/<模块名>`，立即提供 Actions 链接，不等待运行结束；CI 通过后才合主干，失败在同分支修复，不带红灯进入下一步。

### 第 0 步实施与证据边界

- 输入为 `TestSupport/BaselineSupport/CoordinateFixture.swift` 中的纯坐标公式，每个模式按原生尺寸生成 `RGBImage`，无图片 IO、无缩放。
- 48 kHz、幅度 0.8，使用未修改的 Swift 编码器与 WAVEncoder 生成 Robot 36 / Martin M1 / PD 120 各一个 PCM16 单声道 WAV。
- `capture_baselines.py` 校验 WAV 与实际样本元数据，输出相对文件名的 `SHA256SUMS`，CI 再用 `shasum -a 256 -c` 独立复核。
- 每个模式的同一份编码 PCM 送入现有解码器，另存 `*-row-order.json`：比较正序与倒序的平均像素误差，同时记录完成行数。结果可为一致、倒序、无法判定或解码失败；后两类不伪装成方向 bug。
- 行序诊断与 WAV 哈希分开保存。回环只验证编解码链路，不经过 App/PNG 载入器，因此不能据此宣称载入器无 bug。本轮不改载入器；有异常先报告并单独记录。
- 旧 `Tests/Fixtures/testcard.png` 和生成脚本保留为历史素材，已不参与基线；角点断言、PNG 读取、基线缩放代码已移除。
- 本地 Python 测试：25/25，通过；仓库契约与生产源码零差异检查：通过。Swift/Xcode、三个真实 WAV 哈希、实际回环结论：**待 GitHub Actions，尚未完成**。

## ① 工程事实表

| 项 | 已查明事实 |
|---|---|
| Xcode 工程名 / Scheme / Swift 版本 | XcodeGen 工程名与 Scheme 都是 `SSTVEncoder`（`SSTVEncoder/project.yml:1,68`）。SwiftPM tools version 是 5.9（`SSTVKit/Package.swift:1`）；CI 固定 Xcode 15.0.1 并核验 Swift 5.9 compiler（`.github/workflows/ios.yml:28-33`）。App 的 `SWIFT_VERSION: "5.0"`（`project.yml:11`）是 Xcode 的 Swift 5 language mode，不能误改成不受该设置接受的 `5.9`；仓库校验对此有显式测试。 |
| `IPHONEOS_DEPLOYMENT_TARGET` | `17.0`（`SSTVEncoder/project.yml:5-6`）；Package 平台同为 iOS 17（`SSTVKit/Package.swift:8`）。 |
| 模式类型（枚举还是 struct、文件名） | `SSTVMode` 是 `String + CaseIterable` 的公开枚举，另有 `SSTVModeFamily` 枚举；均在 `SSTVKit/Sources/SSTVKit/SSTVMode.swift:3,36`。当前共 15 个 SSTV 模式。HF Fax 是独立的 `HFFaxProfile` struct / `SSTVReceiveSelection.hfFax`，不属于 `SSTVMode`（`SSTVKit/Sources/SSTVKit/SSTVDecodeTypes.swift:3,37`）。 |
| 模式已有属性（分辨率 / 时长 / VIS 字段名） | `width`、`height`、`visCode`、`scanLineCount`、`lineDuration`、`pictureDuration`、`totalDuration`、`sampleCount(at:)`（`SSTVMode.swift:60-87`）。稳定标识可用枚举 `rawValue`。 |
| 编码入口函数签名（同步/异步、返回 Data 还是 URL） | `SSTVEncoder.encode(_ image: RGBImage, mode: SSTVMode, progress: (@Sendable (Double) async -> Void)? = nil) async throws -> PCMBuffer`（`SSTVEncoder.swift:41-45`）；既不直接返回 `Data`，也不返回 URL。 |
| 编码是否按“行”生成样本 | 是。`SSTVEncoder.swift:64-75` 按 `scanLine` 循环，每行调用 `SSTVLineEncoder.segments(...)` 后写入 `ToneWriter`，并回调进度。PD 的一个 radio line 对应两条 raster row。 |
| 播放实现（AVAudioPlayer / AVAudioEngine，所在类） | `PlaybackController` 使用 `AVAudioPlayer` 播放内存中的 WAV，并用 0.1 秒 Timer 发布进度（`SSTVEncoder/Core/PlaybackController.swift:7,63-85,108-110`）。`AVAudioEngine` 只用于麦克风采集。 |
| WAV 导出实现 | `WAVEncoder.encode(_:) -> Data` 将 Float PCM 量化为 little-endian signed PCM16；RIFF 头明确写单声道、16 bit（`SSTVKit/Sources/SSTVKit/WAVEncoder.swift:9-26,47-54`）。App 由 `EncoderViewModel.makeExportDocument()` 包装为 `WAVDocument`（`SSTVEncoder/Core/EncoderViewModel.swift:109-114`）。编码入口固定使用 48,000 Hz（同文件 `:78`）。 |
| 麦克风采集类 + 送样本给解码器的函数 | `MicrophoneReceiver.start()` 安装 `AVAudioEngine` input tap，将输入混成 `[Float]` mono 并通过 `AsyncStream` 送出（`MicrophoneReceiver.swift:62-126`）；`ReceiverViewModel.startMicrophone()` 在 `for await` 中调用 `SSTVStreamDecoder.append(chunk)`（`ReceiverViewModel.swift:107-149`，关键送样本点 `:130-133`）。 |
| 解码是否逐行写像素 | DSP 内部确实按行写入 `pixels`：Robot 36 `SSTVFrameAssembler.swift:197-224`、Robot 72 `:235-263`、PD `:279-319`、Martin/Scottie/Wraase 共用 RGB 行写入 `:379-415`。但当前公开层没有逐行 observer；`append` 只在一个输入 chunk 解出一行或多行后返回整幅 snapshot（`SSTVDecoder.swift:34-50`）。 |
| VIS 检测位置（可插桩点） | `SSTVHeaderDetector.detect(...)` 搜索 leader/VIS 并于 `SSTVHeaderDetector.swift:131-150` 校验 parity、解析 7-bit VIS、构造候选；`SSTVStreamDecoder.detectHeaderIfAvailable()` 于 `SSTVDecoder.swift:96-129` 接收检测结果并创建 frame assembler。可在 assembler 创建后只新增通知，不改变检测算法。 |
| `AVAudioSession` 现有 category / 采样率 | 发射播放为 `.playback/.default`，preferred sample rate 跟随 buffer（`PlaybackController.swift:63-68`）；麦克风目前为 `.record/.measurement/[.duckOthers]`，preferred 48 kHz、20 ms I/O buffer（`MicrophoneReceiver.swift:69-73`）。任务单目标 `.playAndRecord + allowBluetooth + defaultToSpeaker` 与现状不同，须在 T13 胶水层调整。 |
| 现有视图文件：编码页 / 解码页 / TabView 根 | 根和编码页都在 `SSTVEncoder/Features/ContentView.swift`：`ContentView` 是两 Tab 根（`:8-22`），private `EncoderView` 从 `:25` 开始；解码页是 `SSTVEncoder/Features/ReceiveView.swift:7`。当前 Tab 顺序为编码、解码。 |
| 现有 AppIcon 是单尺寸还是全尺寸 | 当前生成脚本只产出一个 `AppIcon-1024.png` universal 项（`scripts/generate_app_icon.py:16-17,105-117`），即单尺寸 iOS 1024 图标；生成目录被 `.gitignore` 忽略。XcodeGen 已设置 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`（`project.yml:67`）。 |
| 是否使用 SPM 依赖 | 是，仅有本地 path package `../SSTVKit`，App 与 App tests 都依赖其 `SSTVKit` product（`project.yml:17-19,31-33,77-80`）。没有第三方 Swift package。 |

## ② 文件职责清单

勘察时仓库共有 53 个 `.swift` 文件；下表逐一覆盖。分类含义：`DSP 核心（禁改）` 仅允许任务单明确批准的观察回调；测试与工程适配代码归入 `胶水层（可改）`。

| 文件 | 一句话职责 | 分类 |
|---|---|---|
| `SSTVEncoder/App/SSTVEncoderApp.swift` | App 入口并挂载根视图。 | 胶水层（可改） |
| `SSTVEncoder/Core/AudioFileLoader.swift` | 协调文件访问，经 AVFoundation 读取并转成 mono Float PCM。 | 胶水层（可改） |
| `SSTVEncoder/Core/CropGeometry.swift` | 计算 aspect-fill 裁剪的缩放、偏移与边界夹取。 | 胶水层（可改） |
| `SSTVEncoder/Core/CropSelection.swift` | 保存裁剪缩放和偏移选择。 | 胶水层（可改） |
| `SSTVEncoder/Core/DecodedImageRenderer.swift` | 将 `RGBImage` 转成 UIKit 可显示的图像。 | 胶水层（可改） |
| `SSTVEncoder/Core/EncoderSessionState.swift` | 隔离编码代次、取消、进度与过期结果。 | 胶水层（可改） |
| `SSTVEncoder/Core/EncoderViewModel.swift` | 管理选图、裁剪、模式、编码进度和 WAV 导出状态。 | 胶水层（可改） |
| `SSTVEncoder/Core/ImagePreparer.swift` | 把 UIKit 原图按模式尺寸和裁剪选择转成精确 `RGBImage`。 | 胶水层（可改） |
| `SSTVEncoder/Core/MicrophoneReceiver.swift` | 请求权限、配置 AVAudioSession、采集并输出 mono PCM chunks。 | 胶水层（可改） |
| `SSTVEncoder/Core/PlaybackController.swift` | 配置播放音频会话、用 AVAudioPlayer 播放并发布进度。 | 胶水层（可改） |
| `SSTVEncoder/Core/PNGDocument.swift` | SwiftUI fileExporter 的 PNG 文档包装。 | 胶水层（可改） |
| `SSTVEncoder/Core/ReceiverSessionState.swift` | 隔离接收代次、输入来源、渐进帧和取消状态。 | 胶水层（可改） |
| `SSTVEncoder/Core/ReceiverViewModel.swift` | 编排音频文件/麦克风输入、渐进解码、图像呈现和 PNG 导出。 | 胶水层（可改） |
| `SSTVEncoder/Core/WAVDocument.swift` | SwiftUI fileExporter 的 WAV 文档包装。 | 胶水层（可改） |
| `SSTVEncoder/Features/ContentView.swift` | 当前两 Tab 根视图及完整编码页面。 | UI（本次重写） |
| `SSTVEncoder/Features/CropEditor.swift` | 手势驱动的照片裁剪编辑 UI。 | UI（本次重写） |
| `SSTVEncoder/Features/ReceiveView.swift` | 当前接收/解码页面。 | UI（本次重写） |
| `SSTVEncoderTests/CropGeometryTests.swift` | 验证裁剪缩放和偏移边界。 | 胶水层（可改） |
| `SSTVEncoderTests/EncoderSessionStateTests.swift` | 验证编码状态机代次、取消和单调进度。 | 胶水层（可改） |
| `SSTVEncoderTests/ImagePreparerTests.swift` | 验证预览与编码 raster 像素/尺寸一致。 | 胶水层（可改） |
| `SSTVEncoderTests/ReceiverAdapterTests.swift` | 验证音频加载适配和接收模式菜单覆盖。 | 胶水层（可改） |
| `SSTVEncoderTests/ReceiverSessionStateTests.swift` | 验证渐进接收状态、代次和进度。 | 胶水层（可改） |
| `SSTVKit/Package.swift` | 定义 Swift 5.9 的 SSTVKit library 与 test targets。 | 胶水层（可改） |
| `SSTVKit/Sources/SSTVKit/HFFaxAssembler.swift` | 按 HF Fax profile 把频率样本组装为灰度传真行。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/RGBImage.swift` | 定义 RGB pixel/raster 及尺寸校验。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SampleClock.swift` | 将累计时长稳定换算为整数样本数。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVColor.swift` | 实现 BT.601/Robot 色差与 SSTV 频率映射。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVDecoder.swift` | 编排流式/整段音频的解调、VIS/时序锁定与帧组装。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVDecodeTypes.swift` | 定义 HF Fax profile、接收选择、检测来源、渐进帧和错误。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVEncoder.swift` | 定义 PCMBuffer 并按扫描行异步生成 SSTV PCM。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVFrameAssembler.swift` | 按各协议时序采样通道并逐行写入 RGB raster。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVFrequencyDemodulator.swift` | 将 Float PCM 解调为瞬时音频频率。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVHeader.swift` | 生成 leader、break、VIS bits 和 stop tone。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVHeaderDetector.swift` | 搜索并校验 SSTV leader/VIS header。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVLineEncoder.swift` | 生成 Robot/PD/Martin/Scottie/Wraase 每条 radio line 的 tone segments。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVMode.swift` | 保存 15 个模式的稳定标识、VIS、分辨率和时序元数据。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVTimingDetector.swift` | 无 VIS 的手动模式下按行同步时序锁定。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/SSTVToneSampler.swift` | 在解调频率数组中测量 tone、通道像素和最佳同步点。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/ToneWriter.swift` | 以连续相位和累计时钟把 tone segments 合成为 Float PCM。 | DSP 核心（禁改） |
| `SSTVKit/Sources/SSTVKit/WAVEncoder.swift` | 把 mono Float PCM 确定性编码为 RIFF PCM16 WAV。 | DSP 核心（禁改） |
| `SSTVKit/Tests/SSTVKitTests/ColorConversionTests.swift` | 回归颜色/频率映射及 Robot 色度平均。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/DecoderTests.swift` | 回归各协议族自环、流式分块、部分帧、时序锁定和取消。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/EncoderTests.swift` | 回归样本数、确定性、进度、取消和输入校验。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/FrequencyDemodulatorTests.swift` | 回归 tone 频率恢复、残余纹波、分块一致性和错误输入。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/HFFaxDecoderTests.swift` | 回归 Contrib HF Fax 解码及不可自动 VIS 识别的约束。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/LineEncodingTests.swift` | 回归所有模式族每行 tone 顺序与持续时间。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/ModeTests.swift` | 回归 15 个模式元数据、样本数、顺序和家族映射。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/RGBImageTests.swift` | 回归 RGB raster 尺寸、像素数和溢出校验。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/TestSupport.swift` | 提供测试图、WAV 二进制读取和异步进度记录辅助。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/ToneWriterTests.swift` | 回归累计舍入、相位连续、极端输入和音调质量。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/VISDetectorTests.swift` | 回归 VIS 检测、偏频容忍、parity 和未知码拒绝。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/VISHeaderTests.swift` | 回归 VIS bit 顺序、parity、唯一性和 header 频率。 | 胶水层（可改） |
| `SSTVKit/Tests/SSTVKitTests/WAVEncoderTests.swift` | 回归 canonical mono PCM16 WAV 头、payload 与边界错误。 | 胶水层（可改） |

## ③ 偏差记录

### T01 预填的四项结论

| 待确认项 | 结论 | 证据与后续处理 |
|---|---|---|
| 解码器能否驱动真实逐行显示？ | **能，使用已有阶段快照** | `append` 完成新行后返回 snapshot（`SSTVDecoder.swift:34-50`），其中 `completedRows` 已公开。UI 节流 15 fps，不新增 observer，不改 assembler。 |
| 编码器能否取进度？ | **能** | `encode` 的 async progress closure 在每个 radio scan line 后调用（`SSTVEncoder.swift:41-45,64-74`）；PD 进度以 radio line 计数，既有测试覆盖。T11 可在胶水/UI 层节流，不改时序。 |
| 能否拿到原始 PCM 做频谱？ | **能** | 在 `ReceiverViewModel.startMicrophone()` 的同一 AsyncStream 消费循环中，把 `chunk` 同时交给电平、FFT 与 decoder。禁止改 tap 内部。 |
| 模式类型是否有时长字段？ | **有** | 编码完成读 `PCMBuffer.duration`，尚未编码读 `SSTVMode.totalDuration`；不新增 `nominalDuration` 或时长计算。 |

### 其他已确认偏差

| 编号 | 现实与任务单差异 | 处理 |
|---|---|---|
| D01 | Windows 本机没有 Swift/Xcode，且用户明确禁止运行 `swift`、`swift test`、`xcodebuild`、`xcodegen`；任务单 R7 要求每卡本地 `xcodebuild`。 | 采用用户明确的平台约束：本机只运行文本/静态/Python 检查；每卡 commit 推送后由 GitHub Actions 执行 SwiftPM、iOS simulator test 与 device build。所有本机 Swift/Xcode 项一律标为 `NOT RUN`，绝不声称通过。 |
| D02 | 任务描述“Swift 5.9”指编译器版本；Xcode build setting 仍使用合法的 Swift 5 language mode 值 `5.0`。 | 保持 `SWIFT_VERSION: "5.0"`；由 Xcode 15.0.1 / `swift --version` 的 CI gate 保证 Swift 5.9。`scripts/tests/test_validation_scripts.py` 已防止误写成 `5.9`。 |
| D03 | 原任务单禁止 `ContentUnavailableView` / `@Observable` 的条款已由用户取消。 | iOS 17 原生 API 可直接使用，无需可用性分支；仍禁止 SwiftData，不为新语法重写既有状态类。 |
| D04 | T21 描述交付目录内含 3 张 PNG，但本次实际附件只有 `sstv-icon-A.svg`、`Contents.json` 和三张预览 PNG；没有名为 `AppIcon-1024*.png` 的三张最终源文件。 | T21 以 SVG 为唯一矢量真源，确定性脚本生成默认/深色/着色 PNG；不内联 base64。主图必须 RGB 无 alpha，深色/着色可按 Contents 规则保留透明。 |
| D05 | Creative Production board 工具在当前会话没有可直接调用入口，只有工作流明确禁止的 nested 入口。 | 不绕过、不伪造 board；设计实现以用户提供的 `redesign.html`、SVG、Contents.json 与三张截图为确定性参考。 |
| D06 | 麦克风会话当前为 `.record` 且路由中断只停止，不会按 T13 自动重启；receiver 完成一帧后也会停止麦克风。 | T13/T18 仅改 App 胶水层与状态机，保留 DSP 算法。真实耳机/蓝牙恢复与连续接收须真机验证。 |

## ④ 进度表

### 总进度（按最新确认的顺序，不按旧 T01–T22 顺序开工）

| 步骤 | 内容 | 状态 |
|---|---|---|
| 0 | 纯算法输入的三模式 WAV 基线与独立行序诊断 | 本地工具与测试完成，待 CI 产出哈希；未开始 UI |
| 1 | Theme、颜色资产、通用组件 | 未开始 |
| 2 | 接收默认的四 Tab 骨架 | 未开始 |
| 3 | 图库存储与图库页 | 未开始 |
| 4 | 发射页、真实时长、进度、叠字与播放 | 未开始 |
| 5 | 接收状态条、电平、连续收图、15 fps 快照显示 | 未开始 |
| 6 | 1024 点 Hann FFT 与 20 fps 瀑布图 | 未开始 |
| 7 | 设置页 | 未开始 |
| 8 | 原 UI 稿十项自检与 WAV 哈希回归 | 未开始 |

旧卡片编号仅作勘察历史引用，不扩大本轮范围；第 0 步先报告三个真实哈希，再进入后续 UI。

### 已完成

| 卡片 | 完成时间 | 耗时 | 结果 |
|---|---|---|---|
| T01 | 2026-09-05 | 约 30 分钟 | 15 项工程事实全部填实；53/53 个 Swift 文件入职责表；四个预确认项均给出能/不能与代码位置。 |

### 已降级 / 平台替代

| 卡片/规则 | 状态 | 原因与替代验证 |
|---|---|---|
| T01 / R7 本地 Xcode 构建 | NOT RUN | Windows 环境且用户明确禁止本地 Swift/Xcode 命令；commit 后由 GitHub Actions 验证。 |
| Creative Production board | NOT RUN | 无合规的 direct board tool；使用已提供的确定性设计源。 |

### 待办

| 下一张卡 | 开始条件 | 计划 |
|---|---|---|
| 第 0 步 | 用户已确认修订方法及临时分支 CI | 推送 `ui/baseline` 并立即报告 Actions 链接；CI 用纯坐标图生成三个 WAV，报告真实 SHA-256 和行序诊断。禁止本机模拟编码或猜测哈希。 |

### T01 完成判定自检

- [x] 工程事实表 15 行全部填实，没有“待定”。
- [x] 文件职责清单覆盖工程内全部 53 个 `.swift` 文件。
- [x] 四条待确认项都有明确结论（能 / 不能 + 文件:行号）。
- [ ] `xcodebuild -scheme SSTVEncoder -sdk iphonesimulator build`：**NOT RUN（D01）；等待 GitHub Actions 替代验证。**
