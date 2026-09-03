# 变更日志

## 1.1.7 - 2026-09-03

### 修复

- 使用 GitHub Actions 支持的 Bash 执行自动发布 workflow 步骤，修复 tag 发布任务启动失败。

## 1.1.6 - 2026-09-03

### 修复

- 修正自动发布 workflow 的版本提取，使用 macOS 系统自带工具，避免 runner 缺少额外命令导致发布失败。

## 1.1.5 - 2026-09-03

### 自动化

- 新增 GitHub Actions tag 发布流程：自动测试、封包、校验 SHA-256 并创建 GitHub Release。

## 1.1.4 - 2026-09-03

### 维护

- 新增第三方依赖来源记录，固定 LAME 4.0 和 mpg123 1.33.7 的上游、Homebrew bottle 与仓库工件 SHA-256。
- 明确 CLI 静态链接 LGPL 库的再分发义务仍待项目所有者或法律顾问裁定。

## 1.1.3 - 2026-09-03

### 维护

- 同步项目规则、进度、阻塞项和 README 的现役发布状态。
- 明确每次代码更新的测试、提交、封包、推送和 GitHub Release 收尾流程。

## 1.1.2 - 2026-09-03

### 新增

- 应用启动后后台检查 GitHub Releases，并在“音声转换”菜单提供手动检查与用户确认后的下载安装。
- 仅接受正式 macOS arm64 Release；下载后验证 SHA-256、压缩路径、Bundle ID、版本和 ad-hoc 代码签名。
- 独立安装 helper 在主应用退出后原子替换 App、重启新版本；安装失败保留旧 App，临时文件自动清理。

## 1.1.1 - 2026-09-03

### 改进

- 音频转换界面新增实时批次和单文件进度反馈，展示当前文件、状态、百分比和成功/失败/取消汇总

## 1.1.0 - 2026-09-01

### 新增

- 统一的“音频转换”“字幕转换”“配对处理”三模块 macOS SwiftUI 界面
- WebVTT → LRC：宽松/严格解析、HTML/karaoke 清洗、可选说话人前缀、UTF-8 无 BOM 输出和预览统计
- Foundation-only 核心工作流模型：递归扫描、隐藏项与符号链接跳过、规范化去重、冲突命名、输入快照、任务状态和最近 30 批次模型
- 大小写不敏感的安全主干配对，支持 `track.mp3.vtt`、`track.flac.vtt`、`track.aiff.vtt` 等伴随字幕，并拒绝歧义配对
- SwiftPM `VoiceConvertCore` 和 `VoiceConvertCLI` 包；CLI 保留旧 `--convert` 参数并增加 `audio`、`subtitle`、`pair`
- 工程统一到 Swift 6，版本号更新为 1.1.0，保留 arm64/macOS 26.0 和现有第三方库配置

### 当前限制

- App 的配对模块已接入成对 MP3/LRC 执行链、统一冲突策略、失败重试、任务快照和最近批次持久化。
- CLI `audio` 已接入 AVFoundation 与仓库内 arm64 LAME/mpg123 静态后端，可实际批量生成 MP3；`pair` 已执行真实 MP3/LRC 成对批处理，并支持 suffix/skip/overwrite、输出目录和一次性 `--yes` 确认。
- Developer ID 签名、公证、stapling 和第三方二进制完整来源核查尚未完成。
- Core/CLI SwiftPM 测试已加入 GitHub Actions workflow，并已由 tag `v1.1.0` 的远程 run 验证通过。

## 1.0.0 - 首个公开整理版本

### 新增

- 原生 SwiftUI macOS 音频转换应用“音声转换”
- WAV、FLAC、AIFF、M4A 批量转换为 MP3
- 拖放、文件夹递归扫描、并发队列、暂停和取消
- 输出冲突保护与可选源文件删除
- MIT 许可证、第三方声明和 GitHub Actions 构建测试配置

### 限制

- 当前仅支持 macOS 26.0+ 和 Apple Silicon（arm64）
- 未配置 Developer ID 签名，未完成 notarization/stapling
- LAME/mpg123 二进制的精确版本、来源可复现性和再分发合规性仍待核查
- 自动化测试尚未覆盖所有输入格式的完整兼容性
