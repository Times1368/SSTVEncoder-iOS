# S3 图库阶段交接

2026-09-09，执行体 codex，分支 `codex/s3-library`。本卡仍在进行中。

已实现文件系统仓库、原子 JSON 写入、PNG/JPEG 缩略图、损坏索引备份与恢复、三列网格、筛选、日期分组、缩放详情、备注、收藏、分享、删除确认及发射记录重用图片/模式的接线。

恢复记录使用未知方向和模式，不推测原始信息。文件读取失败会原样报错；自动加载不删除未入索引的原图。

本机契约与 Python 测试 36/36 通过。新增 Swift 测试、iOS 构建与真机行为均 NOT RUN，等待本分支 Actions；DSP 与冻结哈希未修改。

尚未完成：

- 系统相册直接保存的权限文案与按钮接线。PhotoLibrarySaver 已存在，但尚无调用；必须先按独占工程文件规则单独配置 `NSPhotoLibraryAddUsageDescription`，避免权限缺失崩溃。
- 收发自动入库和连续两帧的端到端验证，仍属于后续收发接线步骤；当前图库不会自行产生记录。
- 多选导出和真机布局/缩放验收。
- 存储删除失败的事务恢复和磁盘故障注入测试。

下一入口：`SSTVEncoder/Features/Library/SSTVLibraryView.swift` 的详情行动区；`SSTVEncoder/Core/Library/SSTVLibrary.swift` 的删除事务。现阶段不标记整张 S3 完成，不合入 main，先检查 CI 编译结果。
