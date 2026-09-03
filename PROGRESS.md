# 当前进度

目标是将音频转换、WebVTT→LRC 字幕转换和配对处理统一为可批量使用、可测试、可发布的 macOS 原生 v1.1.3 工具。

## 已完成并验证

- 旧 VTT/LRC 核心迁移到 `VoiceConvertCore`，保留原有语义测试，并扩展严格/宽松解析、预览统计、编码检测、清洗和冲突结果。
- Foundation-only 工作流模型：递归扫描、隐藏项/符号链接跳过、规范化路径去重、输出命名策略、配对模型、输入快照、任务状态和最近 30 批次模型。
- 设置快照、导入保护、版本化批次 JSON、v0 迁移备份和迁移失败隔离模型。
- SwiftPM CLI 已接入真实 AVFoundation/LAME 音频后端，`audio`、`subtitle`、`pair` 均可执行。
- App 已接入 GitHub Releases 更新检查、正式 arm64 资产筛选、SHA-256/压缩包安全校验、用户确认安装和独立临时 helper；helper 在主 App 退出后原子替换、重启新 App，失败保留旧 App 并清理临时目录。
- 产品名“音声转换”、Bundle ID `com.voiceconvert.app`、arm64 和 macOS 26.0 约束保持不变。

## 当前验证

- `VoiceConvertCore` SwiftPM：73/73 测试通过，包含更新版本、Release 解析、checksum 和 zip-slip 测试。
- `VoiceConvertCLI` SwiftPM：5/5 测试通过，包含真实 AVFoundation WAV→MP3、字幕、配对和退出码测试。
- Xcode Debug build/test：通过；远端 GitHub Actions 对提交 `814d261` 的运行通过。
- Release `v1.1.2` 已发布；包内含独立 `App/音声转换.app/Contents/Resources/Helpers/update-helper`，下载后 SHA-256 校验通过。
- 本轮文档同步目标：让规则、README、CHANGELOG、PROGRESS、BLOCKED 与 v1.1.2 已发布的实际状态一致，并保留历史 Release notes。

## 尚未完成或待补证据

- Developer ID 签名、公证、stapling 和第三方二进制精确来源/再分发核查仍无凭据。
- GitHub Actions 尚未自动生成并上传 Release 资产；当前由 `scripts/export-release.zsh` 在本机生成后上传。

## 历史验证（v1.1.2 发布前）

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

## 后续工作

- Developer ID 签名、公证、stapling 和第三方二进制精确来源/再分发核查仍无凭据。
- GitHub Actions 当前运行测试和 CLI 构建，但不会自动生成或上传 Release 资产；公开发布仍需在本机执行 `scripts/export-release.zsh` 后上传 zip 与 `.sha256`。
- CLI 取消、重试、最近批次的独立进程级证据仍未补齐；Core/App 已覆盖对应状态模型和批次保存。

## 本轮发布命令

- `swift test --package-path VoiceConvertCore --disable-sandbox`：通过，73/73。
- `swift test --package-path VoiceConvertCLI --disable-sandbox`：通过，5/5。
- Xcode Debug build/test：通过。
- `zsh scripts/export-release.zsh 1.1.2`：通过，v1.1.2 zip 与 `.sha256` 已发布。
- `git diff --check`：通过。
