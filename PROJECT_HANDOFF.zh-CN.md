# SSTVEncoder-iOS 项目交接与协作要求

核实日期：2026-09-06。面向项目所有者、Claude 与后续维护者。

本文件是当前进度和已确认要求的入口，不代表所有目标已经实现。用户后续明确指令优先；
`REFACTOR_NOTES.md`、`UI_IMPLEMENTATION.md` 和分阶段设计文档保留历史证据，不能用其中过时的禁令或待办覆盖本文件。

## 1. 项目定位与当前可用版本

- 仓库：[Times1368/SSTVEncoder-iOS](https://github.com/Times1368/SSTVEncoder-iOS)。
- 独立 iPhone/iPad SSTV 收发 App + 可复用、生产源码仅依赖 Foundation 的 `SSTVKit`。
- iOS 17.0+，Swift 5.9 工具链，SwiftUI，XcodeGen；`SWIFT_VERSION: "5.0"` 是合法的 Swift 5 语言模式，不改成 `5.9`。
- 当前 App 版本：**1.1.3（5）**，实现提交 `10cc147d0a680172ffdbb0524a1f1a0266b9e44e`。
- [该提交的 Actions 33956223017](https://github.com/Times1368/SSTVEncoder-iOS/actions/runs/33956223017) 已完成且四个 job 全部成功：Swift 5.9 / iOS 17 兼容、Xcode 16.4 测试、设备版 unsigned IPA 打包、下载产物独立复验。
- [已生成的 unsigned IPA artifact](https://github.com/Times1368/SSTVEncoder-iOS/actions/runs/33956223017/artifacts/9966598976)：`SSTVEncoder-iOS-unsigned-10cc147d0a680172ffdbb0524a1f1a0266b9e44e`。未签名，不等于已上架或可直接安装的正式发行版。
- 用户反馈接收已“基本正常”；中途接收候选已通过合成测试与 CI，**没有同次原始失败音频的完整真机复验，也没有商用品质验收结论**。

### 分支整合边界

| 分支/提交 | 内容 | 本次整合处理 |
|---|---|---|
| `ui/design-system` / `40c4132` | Theme、四 Tab、颜色资产编译修复 | 已包含在绿色接收分支历史中，一并进入 main |
| `ui/receive-quality` / `10cc147` | 接收质量、Robot 72 同步、中途锁定 | CI 全绿，作为 main 的代码基点 |
| `codex/t02-baseline-capture` / `d7453de` | 旧基线采集工具准备 | 属于下面的基线分支历史，不作为另一个产品版本 |
| `ui/baseline` / 远端 `6f8e345`、本地 `8018416` | 算法测试图生成器、原始 WAV 归档、诊断解耦 | 原 run 的诊断失败，后续本地修复未经 CI；在 `ui/baseline-integration` 验证后再合 main |

不能为实现“合并全部分支”而忽略未通过的 CI、用整树覆盖回退接收修复，或通过 `ours` 合并丢掉独有提交。
保留原分支与提交历史，不强推、不删除分支。Claude 的功能工作从远端最新 `main` 分出，不从旧基线分支分出。

## 2. 实现进度：能力与缺口

| 模块 | 当前已实现 | 尚未完成/验收 |
|---|---|---|
| SSTV 编码 | 15 模式；选图、裁剪/缩放、编码 raster 预览、异步进度/取消、本机播放、48 kHz 单声道 PCM16 WAV 导出 | 新版行动区、模式 chips、叠字/呼号、播放扫描线、发射入库 |
| SSTV 解码 | 音频文件/显式开麦；VIS 自动、手动时序、渐进快照、完整/片段 PNG 导出 | 连续多帧接收与持久保存、完整接收仪表页、复杂弱信号互操作验收 |
| 接收质量 | 带通/FIR 抗谐波、完整同步边沿判定、初始周期锁定、行时钟跟踪；采集队列溢出/硬件时间缺口显式报错 | 不承诺任意频偏、任意断流或所有电台声学路径均可靠；继续用真实录音量化 |
| 中途接收 | 漏 VIS 后根据重复行同步自动候选锁定；Robot 色度标记消歧；显示片段和未知原始行号 | 多普勒/弱信号/晚启动真机矩阵；不能恢复未收到的像素和文字 |
| HF Fax | 独立 `HFFaxProfile`，手动 IOC 576 / 120 LPM 渐进灰度接收 | 保持独立入口，不声称有 VIS 自动识别或 HF Fax 发射 |
| 设计系统 | Theme、18 个 Any/Dark 颜色、通用卡片/按钮/进度/扫描线组件；资产打包修复 | 全页面参考稿一致性、大小字体/小屏可达性真机验证 |
| 四 Tab | 接收 / 发射 / 图库 / 设置，接收默认，inline 导航标题 | 图库、设置目前明确是占位骨架；不能因有 Tab 就标为已交付 |
| 图库与设置 | 关于、版本、原隐私说明；骨架跳转 | JSON 持久化、缩略图、收藏/详情/重发、偏好设置与空间管理 |
| CI/交付 | 双 Xcode 测试、设备构建、无签名 IPA、安全/完整性复验 | 签名分发、App Store 材料、正式设备/性能/可访问性验收 |

15 个 `SSTVMode`：Robot 36 Color / 72 Color；PD 50 / 90 / 120 / 160 / 180 / 240 / 290；
Martin M1 / M2；Scottie S1 / S2 / DX；Wraase SC2-180。
“Contrib / HF Fax”是独立接收入口，不是第 16 个 VIS 模式。

## 3. 已确认接口与文件职责

| 位置 | 接口/职责 | 协作注意点 |
|---|---|---|
| `SSTVKit/Sources/SSTVKit/SSTVEncoder.swift` | `encode(_ image: RGBImage, mode: SSTVMode, progress: (@Sendable (Double) async -> Void)? = nil) async throws -> PCMBuffer` | 直接使用现有进度；完成后时长读 `PCMBuffer.duration` |
| `SSTVKit/Sources/SSTVKit/SSTVMode.swift` | `SSTVMode` 枚举；`rawValue`、`width`、`height`、`visCode`、`scanLineCount`、`lineDuration`、`pictureDuration`、`totalDuration` | 未编码时预估用 `totalDuration`，不从模式名取数字、不写 UI 时长表 |
| `SSTVKit/Sources/SSTVKit/SSTVDecoder.swift` | actor `SSTVStreamDecoder`；`append(_ samples: [Float]) throws -> SSTVDecodedFrame?`、`finish() throws -> SSTVDecodedFrame` | actor 外调用用 `try await`；无需仅为跨 actor 调用把声明强行改成 async |
| `SSTVKit/Sources/SSTVKit/SSTVDecodeTypes.swift` | 快照包含 `completedRows`、`mode`、`image`、`isComplete`、`detectionSource`、可选 `progress` | `.lateEntry` 的 `progress == nil`；本地画布填满不等于原始传输完整 |
| `SSTVKit/Sources/SSTVKit/SSTVLateEntryDetector.swift` | 无 VIS 候选锁定；四个真实同步脉冲、周期约 ±0.5% 验证、拒绝歧义 | 频偏、时钟偏差分开处理；不通过放松断言掩盖误锁 |
| `SSTVKit/Sources/SSTVKit/SSTVFrameAssembler.swift` 等 DSP 文件 | 按协议组装行、时钟/解调/色彩 | UI 工作不得改；后续接收算法修复另立范围、录音与回归证据 |
| `SSTVEncoder/Core/ReceiverViewModel.swift` | `startMicrophone()` 消费 `MicrophoneCapture` 的流并 `append(chunk)`；`decodeAudioFile` 文件解码 | 目前完整帧后仍 `break` 并停麦；连续接收不能只删掉 break，还要处理帧边界和同块尾部 |
| `SSTVEncoder/Core/MicrophoneReceiver.swift`、`MicrophoneCaptureBuffer.swift` | AVAudioEngine、权限/会话、有界连续 PCM 交接 | 不改 tap 来挂 UI；不可悄悄丢块后把不连续音频拼起来 |
| `SSTVEncoder/Core/PlaybackController.swift` | AVAudioPlayer、每 0.1 秒进度更新、`.playback` | 扫描线在 UI 插值，不提高播放器定时器频率 |
| `SSTVEncoder/Core/EncoderViewModel.swift`、`ImagePreparer.swift` | 选图、裁剪、模式与 raster；编码任务状态 | 换模式保留图片和叠字；UI 改造不顺带修图像方向 |
| `SSTVEncoder/Features/ContentView.swift`、`ReceiveView.swift` | 根 Tab/现有发射页面、接收页面 | 收发页面还不是最终稿；图库/设置骨架在 `AppShellViews.swift` |
| `SSTVEncoder/Features/DesignSystem/`、`Resources/Theme.xcassets` | 共用 token、颜色与组件 | 复用而非另造颜色/间距系统 |
| `SSTVEncoder/project.yml`、`.github/workflows/ios.yml` | 工程真源与 CI | 不提交生成的 xcodeproj；共享构建文件由集成者统一修改 |

`append` 只返回阶段快照，并不公开“已消费到输入样本的哪个位置”。若连续收图需要额外帧边界接口，
先列出现有接口缺口及最小方案供用户确认，不假定它已经存在，不重写 assembler 来凑 UI 需求。

## 4. 不可回退的产品/技术约束

1. UI 分支不改 VIS 表、编码时序、颜色转换、重采样、解码器/assembler；已经单独授权实施的接收质量修复必须保留。
2. 不引入第三方 App 运行库、SwiftData、Radio Lite 远控/PTT/CAT 业务。图片主体用文件系统 + JSON。
3. iOS 17 原生 API 可直接用，包括 NavigationStack、presentationDetents、ContentUnavailableView、symbolEffect、@Observable；但新状态管理跟现有 ObservableObject 一致，不为语法重写旧代码。
4. 麦克风只在用户点击后启动。默认接收 Tab、入库、解码完成或自动识别都不构成自动开麦授权。
5. 两段文案逐字保留，可以调整位置：
   - 「仅生成、播放和导出音频；不会连接或控制电台发射。」
   - 「只有点击“启动麦克风”后才会请求并使用麦克风；原始音频不会保存或上传。」
6. 所有界面提示使用简体中文，协议/模式名使用既有标准名称；时长、dB、进度、频率数字用 `.monospacedDigit()`。
7. 片段不能伪造未收到的像素、原始行号、整图完成率或“成功恢复整次通联”。缺 VIS 与多普勒频偏是不同问题。
8. 不把自环合成测试等同独立互操作、真机声学测试或商用认证；不通过更新冻结哈希/放宽测试来制造成功。

## 5. 完整目标 UI 与交互（待实施部分不能缩水）

### 图库：建议 Claude 的第一块独立任务

- `Documents/SSTVLibrary/index.json` 原子写入；`images/<uuid>.png`；`thumbs/<uuid>.jpg`，长边 320。
- 索引字段：id、date、direction（rx/tx）、modeID、modeName、width、height、note、isFavorite。
- JSON 解析失败不崩溃，扫描 images 重建；无法恢复的模式/方向等元数据必须标明未知，不编造。
- 三列网格，今天/昨天/日期分组；全部/接收/发射/收藏筛选；滚动只读缩略图。
- 接收绿点、发射蓝点、模式标签。详情支持缩放、分享、存相册、收藏、删除；发射记录支持“用这张图再发一次”。
- 每帧独立记录；第二张绝不能覆盖第一张；重启仍在。先测原子性、损坏恢复、缩略图、两帧保存、删除一致性，再接 UI。

### 发射

- 真实模式宽高比裁切/补边预览；文字在模式原生尺寸绘制并带黑色描边；空白添加、点击编辑、拖动移动，设置呼号可插入。原相册照片不改。
- 常用 chips 默认 Robot 36 / Martin M1 / Scottie S1 / PD 120，加“全部 ›”；全部 sheet 按 Robot/PD/Martin/Scottie/Wraase 分组，仅列 15 个 VIS 模式。
- chip 副标题为时长；列表含模式名、时长、分辨率、VIS、中文说明；规格行等宽数字。未编码用 `totalDuration`，已编码用 `PCMBuffer.duration`。
- 主按钮“生成并播放”，次级“仅生成”“导出 WAV”；取消独立空输出卡。禁用原因明确显示“先选择一张照片”或“先完成编码”。
- 播放变红色“停止播放”，显示进度/时间；扫描线跳过实际前导段：`max(0, (t - headerDuration) / (totalDuration - headerDuration))`，UI 用 0.1 秒线性动画并夹取有效显示范围。
- 换模式不清空图片/叠字；播放完成可自动存渲染后的 tx 图。免责声明放右上角信息 sheet，首次弹一次。

### 接收与连续收图

- 常驻 44 pt 状态条：状态点、文字、电平条、dB。未启动 / 监听中·自动识别 / 接收模式和行数 / 已完成 / 出错；监听呼吸动画。中途片段继续保留诚实标记。
- 同一批 `MicrophoneCapture` 流样本并联计算 RMS/峰值与 FFT；不要开第二个流迭代器抢样本，不改 tap 内部。
- RMS 用 0.2 秒时间常数平滑，dBFS 用 `20*log10`；<−40 灰、−40～−12 绿、−12～−3 黄、>−3 红。
- 连续 3 秒峰值 >−1 dBFS：黄色“输入过载，请调低电台音量”；连续 10 秒 RMS <−45 dBFS：“几乎没有输入，检查音量与线路”。用音频样本时间判断连续性。
- 4:3 恒深色画布，等待说明/监听计时；快照 UI 节流 15 fps，按 `completedRows` 遮住未接收行，白色扫描线推进。
- 麦克风主按钮高权重，停止为红色；导入音频、模式为次级。HF Fax 与自动识别 SSTV 并列，保持独立 profile/既有行为。
- 完成帧保存并提示“已保存到图库”2 秒，重置 decoder 继续流；回到监听状态，最近图像保留到下一帧。完成行动条在控制区上方，不藏在滚动底部。
- 处理停止、切 Tab、视图销毁、后台、来电/路由变化及常亮复位。当前 `.record/.measurement` 不等于目标 `.playAndRecord + [.allowBluetooth, .defaultToSpeaker]` 已交付；会话调整必须独立验证输入处理和采样连续性，不牺牲已修复画质。

### 瀑布与设置

- Accelerate vDSP 1024 点 Hann 窗 FFT；48 kHz 下约 21 ms/列；时间从右进，纵轴 500–2800 Hz，参考 1200/1500/2300 Hz。
- 320×128 RGBA 缓冲左移一列、右侧写新列，CGImage + `Image(decorative:)`、最近邻；132 pt 高、固定 20 fps，不按音频 callback 刷 UI。
- `@AppStorage` 偏好：呼号、默认模式、4 个常用模式、tx/rx 自动入库、常亮、跟随/浅/深、瀑布配色；另有空间统计/清理与关于/全文隐私说明。
- 自动入库默认开启，显式关闭偏好后尊重用户选择；关闭/失败不应导致无法导出已收到图像。存储清理需明确范围和可恢复性。

### 设计 token

Accent `#2F6BFF` / 深色 `#4C86FF`；绿 `#30D158`、黄 `#FF9F0A`、红 `#FF453A`；
仪表底两种外观均 `#060A14`。彩条 `#E4ECF8 #FFD84A #2FD3E6 #34CF6A #E052C6 #FF4A3D`。
8 pt 网格、卡片圆角 16、主按钮高 52 且全圆角、状态条 44、瀑布 132。
颜色从现有 Any/Dark Asset Catalog 取，不在页面硬编码；选中描边/进度用既有彩条渐变。

## 6. 编码基线与诊断证据

冻结值及完整环境见 [Tests/Baseline/README.md](Tests/Baseline/README.md)。三个 WAV 是 **Swift `SSTVEncoder.encode`** 输出，Python 只编排/校验，不是参考编码器代用品。

| 模式 | 样本数 / 48000 的秒数（含前导） | WAV SHA-256 |
|---|---:|---|
| Robot 36 | 36.910000000 | `2acfaaab8b5dd14b17f283f1d4b05815259e1eb60ff461d69fe33ae3d14fa3fb` |
| Martin M1 | 115.200166667 | `c8d217e84aeb81c83a76d00b83b4791fd3b9f370d65112d280e2c29c5c6c6251` |
| PD 120 | 127.013041667 | `8553fc7fb48ac291245df7f9bbd79bf210cb209a39115ce04dd2416ab0dc5e52` |

源 commit `6f8e34554e2967f4bed3f52d0932f39962e39913`，Xcode 15.0.1 / Swift 5.9 / arm64 / Release，48000 Hz / mono / PCM16 / amplitude 0.8。
基线输入是各模式原生尺寸的算法 RGBImage：`r=(x*8)%256; g=(y*8)%256; b=((x+y)*4)%256`，没有 PNG 载入器。
时长与 `SSTVMode.totalDuration` 差异均不到一采样；不可把模式名数字当总时长。

旧基线 job 在 WAV、SHA-256 和上传成功后，被独立行序报告阻断。原报告 Martin M1 为 consistent、Robot 36/PD 120 为 inconclusive，没有 reversed 结论。
不得写“载入器已证实翻转”或“所有模式行序已验证”；当前 UI 任务不改载入器。基线分支将报告改成不阻断的诊断，原报告不篡改，也不重跑旧 workflow 来覆盖证据。
绿色接收分支已有 `EncoderBaselineTests`，固定 Swift 5.9 Release CI 比较这三个哈希，结果在 `receive-quality-xcode15-<commit>` artifact 中。

## 7. Claude / Codex 协作建议与 Git 规则

建议先让 Claude 做“图库存储层 + 图库页”，后续再做设置/发射 UI；Codex 保持接收 DSP、采集连续性、基线和 CI 集成。这是建议分工，未替用户启动/指派任何代理。

- 每个执行体使用独立 clone/工作目录与短分支；同一工作目录任何时候只有一个 Git 写入者。
- 用户已禁止本任务新开并行子代理；Claude 是用户另行启动的协作者，不据此授权 Codex 开子代理。
- Claude 第一块建议新增 `SSTVEncoder/Core/Library/`、`SSTVEncoder/Features/Library/` 和相应 `SSTVEncoderTests`。这是待创建路径，当前没有可假定存在的 `LibraryStore`。
- `ContentView.swift`、`AppShellViews.swift`、`ReceiverViewModel.swift`、`project.yml`、workflow、全局设置是共享接线点；开始修改前记录所有者，另一个执行体暂停改同文件。新接口需连同调用点和测试提交，不留假接口。
- 从最新 `main` 建功能分支，先写测试，再实现，一块一个清晰提交。推送后立即给出 Actions 链接，不等待结果；通过后再由唯一集成者合 main。失败留在同一分支修。
- 不 force push，不重写他人提交，不默认删除远端分支，不触碰未知未提交修改。
- 本机 Windows 不运行 `swift build/test`、`xcodebuild`、`xcodegen`；Swift/XCTest/IPA 均交 GitHub Actions。本机检查仅限脚本/静态等适用项。
- 本机命令必须非交互、关闭标准输入、显式超时不超过 120 秒；Git/SSH 禁止密码/首次主机确认提示。不运行 auth login、首次 SSH 确认或交互式 rebase。
- 不上传令牌、签名密钥、描述文件、真实用户照片/录音、构建缓存或 IPA/ZIP 到源码仓库。上述已批准的合成 WAV 基线是有来源和冻结哈希的测试数据例外。图标用生成脚本，不在补丁内联 base64。
- 每完成文件报告一行进度。交付必须说明 commit、Actions、通过/失败/未运行、影响文件与剩余风险，不以“静态检查通过”代替 iPhone 行为验证。

可直接给 Claude 的起始任务：

> 阅读 PROJECT_HANDOFF.zh-CN.md 与现有 Theme、Tab 骨架。从远端 main 的新分支开始，先报告准备修改的文件和图库测试方案，再按 TDD 实现文件系统图库及图库页。完整保留第 5 节图库要求，不修改 SSTVKit、麦克风、播放和 CI。共享 Tab 接线改动单列；不要假设已有 LibraryStore。提交后给出测试证据和未验收项，由唯一集成者合并。

## 8. 完成顺序与商业交付门槛

当前建议顺序：基线整合 CI → 图库存储/图库 → 发射 → 接收连续监听/仪表 → 瀑布 → 设置 → 全量自检。
设计系统/四 Tab 已有基础；近期接收修复不代表后续 UI 卡片已完成。

原十项验收均需记录证据，尚未整体通过：

1. 同图同模式，改造前后 Swift WAV SHA-256 一致，使用固定工具链。
2. 四 Tab 首屏无滚动可达主操作，覆盖小屏/大字体；所有导航小标题。
3. 开麦 1 秒内电平响应；3 秒过载和 10 秒静音告警真实触发。
4. 输入 1500 Hz，瀑布正确频率位置出现亮线。
5. 完整 SSTV 音频逐行落图、行数递增，未收到部分保持深底。
6. 连续解码两帧，各自入库，第一张不被覆盖。
7. 杀 App 重开，记录和图片仍可读，损坏索引可修复。
8. 换模式保留图片及叠字，预览与实际编码 raster 一致。
9. 播放扫描线扣除前导音，与音频进度误差小于 1 秒。
10. 播完、停止、后台、切 Tab/销毁后，常亮与音频资源正确复位。

另补中途接收：15 模式晚启动、Robot 36 奇偶色度、Robot 72 频偏/时钟偏差、纯载波/噪声不误锁、跨块/缓冲裁切、未知行号与片段导出语义。
正式可商用还要覆盖外部独立编码器录音互操作、最低支持设备、蓝牙/有线/声学输入、来电/路由变更、内存/耗电/长时运行、VoiceOver/动态字体、签名安装与发布材料。
凡没有实际执行的数据都标为“未运行/待真机”，不宣称达到商用标准。
