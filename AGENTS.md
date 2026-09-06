# AGENTS.md — 双执行体协作规则

本仓库由两个 AI 执行体同时维护：

| 执行体 | 运行环境 | 能力边界 |
|---|---|---|
| Codex | 用户的 Windows 本机 | 无 Xcode、无 Swift。只能做文本/静态/Python 检查，全部编译与测试依赖 GitHub Actions。 |
| Claude | Linux 云容器 | 无 Xcode。可能可在 Linux 上运行 `swift test --package-path SSTVKit`（Foundation-only），但该结果不等同于 CI 结论。 |

本文件是协作规则的唯一真源。`CLAUDE.md` 仅指向本文件，两边规则必须完全一致。
项目内容与进度的真源是 `REFACTOR_NOTES.md`。

## 1. 身份与署名

- 每个提交必须带 trailer，标明执行体：
  - Codex：`Assisted-by: codex`
  - Claude：`Assisted-by: claude`
- 分支前缀强制归属：Codex 用 `codex/<卡片号>-<短名>`，Claude 用 `claude/<卡片号>-<短名>`。
- 禁止再使用 `ui/*`、`feature/*` 等无归属前缀。

## 2. 规则真源与修改方式

- 项目规则、DSP 冻结范围、验收口径，只写在 `AGENTS.md` 与 `REFACTOR_NOTES.md`。
- 这两个文件的「规则性内容」只允许在 main 上、由单独的提交修改，禁止与代码改动混在同一条分支里。
  规则性内容指：`AGENTS.md` 全文，以及 `REFACTOR_NOTES.md` 的「原则」段、「① 工程事实表」、「③ 偏差记录」、「DSP 解冻记录」。
- 特性分支上只允许向 `REFACTOR_NOTES.md` 的「④ 进度表 / 已完成」表追加自己卡片的一行执行记录，不得改动其他段落。
- 发现规则与代码现状不符时，先停下并向用户报告，不得自行以代码为准改规则，也不得以过期规则为由回退代码。

## 3. 任务认领

- `REFACTOR_NOTES.md` 的总进度表设「负责人」列，取值 `codex` / `claude` / 空。
- 开工前必须在 main 上提交一次只改负责人列的 commit，message 为 `chore: claim <卡片号>`。
- 没有认领记录的卡片视为未开工，另一方可以接管。
- 同一时间每个执行体最多认领 1 张卡片。

## 4. 独占文件（一次只允许一方修改）

以下文件跨模块生效，git 会静默 auto-merge 出语义正确性错误（合得上但是错的），必须串行修改：

- `scripts/validate_project.py`
- `scripts/tests/test_validation_scripts.py`
- `.github/workflows/ios.yml`
- `SSTVKit/Package.swift`
- `SSTVEncoder/project.yml`
- `AGENTS.md`、`CLAUDE.md`、`REFACTOR_NOTES.md`

规则：

- 修改上述任一文件前，必须先确认远程没有另一方的未合并分支正在改同一个文件（`git fetch --prune` 后逐分支 `git diff --name-only main..<branch>`）。
- 修改上述文件的分支必须只做这一件事，且优先合并，不得与业务改动同分支。

## 5. 分支纪律

- 一张卡片一条分支，一条分支不超过 3 个提交。
- 禁止在未合并的分支上再开分支（禁止 stacked branch）。
- 分支从开出到合并或废弃，不超过 24 小时。
- 合并前必须 `git fetch` 后 rebase 到最新 main 并重跑 CI；不得用「反正 git 没报冲突」作为可合并的依据。
- 合并后立即删除远程分支。

## 6. DSP 冻结范围

- `SSTVKit/Sources/SSTVKit/` 是受保护的 DSP 核心。
- 未经用户在会话中明确书面授权，禁止修改 VIS 编解码、行时序与行时钟、色彩转换、重采样、tone 频率映射的行为。
- 每一次解冻必须在 `REFACTOR_NOTES.md` 的「DSP 解冻记录」表登记：日期、授权原文摘要、涉及文件、对应卡片、执行体。
- 另一方发现 DSP 目录被改动而解冻记录中没有对应行时，不得跟随修改、不得自行回退，必须先向用户确认。

## 7. 编码基线（最高优先级门禁）

- `SSTVKit/Tests/SSTVKitTests/EncoderBaselineTests.swift` 中的三个 SHA-256 是冻结值，来源与工具链记录在 `Tests/Baseline/README.md`。
- 任何情况下禁止为了让测试变绿而修改这三个哈希。哈希变化说明编码链路行为变了，必须先报告并等用户裁决。
- 只有用户明确要求重新冻结基线时才允许更新，且必须同步更新 `Tests/Baseline/README.md` 的生成 commit、Actions run 链接与工具链信息。

## 8. 验证纪律

- 两个执行体都没有 Xcode。禁止声称本机通过了 `swift test` / `xcodebuild` / `xcodegen`。
- 本机允许运行：`scripts/validate_project.py`、`scripts/tests/` 下的 unittest、其他纯 Python 与文本检查。
- Claude 若在 Linux 上运行 SwiftPM，只能针对 `SSTVKit`，报告中必须注明「Linux Swift，非 CI 结论」，不得替代 macOS CI 结论。
- 任何「通过」的结论必须附 GitHub Actions 的 run 链接作为证据。未跑完的一律写 `NOT RUN`。

## 9. CI 使用

- workflow 已启用 concurrency 分组，同一分支的新推送会取消该分支进行中的旧 run；main 不取消。
- 禁止在 5 分钟内对同一分支连续强推超过 2 次。
- 禁止在 workflow 中写死 commit SHA，或使用 `github.ref == 'refs/heads/<某特性分支>'` 这类只在该分支成立的条件——合并到 main 后会变成死代码或错误门禁。
  一次性的诊断任务用 `workflow_dispatch` 手动触发，不要挂在 push 上。

## 10. 交接

- 卡片完成后在 `REFACTOR_NOTES.md` 的「已完成」表补一行：卡片号、执行体、完成时间、CI run 链接、结果。
- 未完成即交接时，必须写明：当前分支名、已完成到哪一步、下一步的具体入口（`文件:行号`）、以及尚未验证的项。
