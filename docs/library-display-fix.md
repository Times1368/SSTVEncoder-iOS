# 图库空白修复（S3 后续）

2026-09-19，codex，分支 `codex/s3-library-display-fix`，基于 main `270be8c`。

根因：图库已有索引和显示能力，但 ContentView 的接收页面没有共享图库，ReceiverViewModel 的最终结果没有保存入口；发射播放结束也没有入库回调。没有记录产生，打开图库始终显示空状态。远端 `claude/s3-receive-archive` 核实时没有领先 main 的提交，未改动该分支。

修复：接收页注入根视图的同一个 SSTVLibraryStore，最终解码结果保存为独立 rx 记录；部分/中途接收写入明确备注，可手动保存停止后的画面。成功保存刷新共享 records，失败保留画面并给出重试/PNG 导出提示。正常播放完成以播放启动时捕获的图像和模式入库 tx，取消/失败不入库，迟到的旧播放器回调不能影响新播放器。

新增测试：导入 Swift 编码器生成的 WAV，先打开空图库，再经真实 ReceiverViewModel 解码，验证共享图库记录、手动重复保存防护、重载和缩略图可读；相同内容的两帧保存不同 UUID，片段备注保持未知行号语义。

本机契约与 Python 测试 36/36 通过；新增 Swift/XCTest 与 iOS 行为待 Actions，真机 NOT RUN。DSP、冻结编码哈希、录音采集和连续监听行为未改变。

旧版本没有保存的历史图像不能从空索引恢复，需重新导入原始录音或重新接收。下一入口：本分支 Actions 新增 ReceiveLibraryIntegrationTests；CI 通过后才合并 main。本修复不代表整个图库、相册权限或连续接收改造均已完成。
