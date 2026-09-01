# 当前进度

目标是将音频转换、WebVTT→LRC 字幕转换和配对处理统一为可批量使用、可测试、可发布的 macOS 原生 v1.1.0 工具。

## 已完成并验证

- 旧 VTT/LRC 核心迁移到 `VoiceConvertCore`，保留原有 34 条语义测试，并扩展严格/宽松解析、预览统计、编码检测、清洗和冲突结果。
- Foundation-only 工作流模型：递归扫描、隐藏项/符号链接跳过、规范化路径去重、输出命名策略、配对模型、输入快照、任务状态和最近 30 批次模型。
- 设置快照、导入保护、版本化批次 JSON、v0 迁移备份和迁移失败隔离模型。
- SwiftPM CLI 已接入真实 AVFoundation/LAME 音频后端：`audio` 预检与 MP3 批处理、`subtitle`、`pair` 均可执行，保留 `--convert` 兼容参数和退出码约定。
- App 首版三模块 `音频转换`、`字幕转换`、`配对处理` UI；产品名、Bundle ID、arm64、macOS 26.0 和第三方库引用保持不变。
- Swift 6 工程集成；版本号为 1.1.0。
- 配对核心已修复 `.flac/.aiff` 伴随字幕主干解析、严格一对一匹配、未匹配音频提示；输出规划器已拒绝相对路径穿越和输入/输出根目录重合。
- CLI `VoiceConvertAudioBackend` 已在 SwiftPM 中静态链接仓库内 arm64 `libmp3lame.a`/`libmpg123.a`，使用 AVFoundation 解码、LAME 分块编码、重新解码校验、临时文件和原子发布。
- CLI `audio` 已支持真实批量 MP3、`--check`、`--output`、`--policy suffix|skip|overwrite` 和 `--yes`；`pair` 已接入真实 MP3/LRC 父子任务执行链。
- CLIKit 已拆出可测试入口，保留 `--convert`、`audio`、`subtitle`、`pair` 和退出码 0/1/64/66/69。
- App 安全作用域书签已覆盖启动恢复、无效授权清理、目录选择、访问会话和清除授权；设置导入导出仅处理普通 `SettingsSnapshot`，保留书签、最近批次和运行中任务；三语 String Catalog 已实际编译为 `en`、`ja`、`zh-Hans` bundle 资源；诊断报告使用路径/状态脱敏 JSON 并可导出。

## 当前验证

- `VoiceConvertCore` SwiftPM：66/66 测试通过。
- `VoiceConvertCLI` SwiftPM：5/5 测试通过，包含真实 AVFoundation WAV→MP3、字幕、配对和退出码测试。
- `swift build --package-path VoiceConvertCLI --product voiceconvert`：通过；产物为 arm64 Mach-O，LAME 符号已静态链接。
- Xcode Debug build：通过（`** BUILD SUCCEEDED **`）。
- Xcode XCTest：12/12 通过（`** TEST SUCCEEDED **`），包括 4 条书签、设置导入导出和诊断脱敏测试。
- `git diff --check`：通过。
- 不可读输入反向验证：将真实 WAV 权限设为 `000` 后，CLI `audio` 返回 `exit=1`，stderr 为 `FAILED ... 无法读取输入音频 ... error -54.`；恢复权限 `0644` 后返回 `exit=0`，stdout 为 `CREATED .../scene.mp3`，输出存在。
- 动态库缺失反向验证：从 Xcode App bundle 临时移走 `Contents/Frameworks/libmp3lame.dylib` 后，启动返回 `exit=134`，stderr 为 `dyld: Library not loaded: @rpath/libmp3lame.dylib`；恢复原文件后加载跟踪不再出现缺失错误，`library-present=yes`，进程在受控终止下返回 `137`，未将该生命周期退出码冒充业务成功。

- `v1.1.0` 已通过 PR #1 合并到 `main`，合并提交为 `3dec002c1b13c1928faadd26be38d7ea4c30c831`；GitHub Release 已发布：https://github.com/michiru233/Hiko-VoiceConvert/releases/tag/v1.1.0。
- Release 资产 `Hiko-VoiceConvert-v1.1.0-macos-arm64.zip` 和 `.sha256` 已上传；下载后 SHA256 校验通过，App/CLI/动态库均为 arm64，包内含许可证、NOTICE、LICENSE 和 README，未含测试 bundle、build 缓存、`.zcode`、临时文件或 `__MACOSX`。
- tag `v1.1.0` 的远程 GitHub Actions run `33501853200` 与发布后 `main` run `33502128860` 均全部通过：SwiftPM Core/CLI/CLI build 和 Xcode App/XCTest 均为绿色。
- 文档同步完成：AGENTS.md、README、CHANGELOG、PROGRESS、BLOCKED 已更新到 v1.1.0 现役状态；`.gitignore` 增加 `**/.build/` 防止 SwiftPM 缓存误提交。
- 修复用户反馈的“应用程序已损害”：根因是发布包内 App 未签名，下载文件带 quarantine 标记时 macOS 报 damaged。`scripts/export-release.zsh` 现在对 App/CLI/动态库做 ad-hoc 签名，校验文件改为纯文件名；已重新上传 v1.1.0 资产并端到端验证（下载→校验→解压→签名校验→CLI 运行）。用户仍需右键打开或 `xattr -dr com.apple.quarantine` 一次，因为未公证。

## 尚未完成或待补证据

- Developer ID 签名、公证、stapling 和第三方二进制精确来源/再分发核查仍无凭据。
- GUI 自包含导出目录和 CLI 取消/重试/最近批次进程级证据仍可由后续开发完成。
- 不可读输入与动态库缺失均已完成独立反向验证；恢复后的 GUI 进程生命周期退出码已单独标注，未作为业务成功证据。

## 本轮命令

- `swift test --package-path VoiceConvertCore --disable-sandbox`：通过，66/66。
- `swift test --package-path VoiceConvertCLI --disable-sandbox`：通过，5/5。
- `swift build --package-path VoiceConvertCLI --product voiceconvert`：通过。
- 三个 CLI 真实 fixture 命令：均返回 0 并生成预期 MP3/LRC。
- CLI 负向 fixture：skip/未确认覆盖/损坏 WAV/坏 VTT 均返回 1；`--yes` 覆盖返回 0；无 `.tmp` 残留。
- `xcodebuild -project VoiceConvert.xcodeproj -scheme VoiceConvert -configuration Debug build CODE_SIGNING_ALLOWED=NO`：通过。
- `xcodebuild -project VoiceConvert.xcodeproj -scheme VoiceConvert -configuration Debug test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`：通过，12/12。
- `git diff --check`：通过。
