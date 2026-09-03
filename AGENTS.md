# Hiko-VoiceConvert 项目规则

## 项目定位

Hiko-VoiceConvert（产品名“音声转换”）是原生 macOS SwiftUI 音声处理工具，提供三条平级工作流：音频转 MP3、WebVTT→LRC 字幕转换、按安全主干名的音频/字幕配对处理；CLI 提供同名 `audio`、`subtitle`、`pair` 子命令。

## 构建与测试

在项目根目录执行：

```bash
xcodebuild -project VoiceConvert.xcodeproj -scheme VoiceConvert -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO
xcodebuild -project VoiceConvert.xcodeproj -scheme VoiceConvert -configuration Debug -sdk macosx test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
swift test --package-path VoiceConvertCore --disable-sandbox
swift test --package-path VoiceConvertCLI --disable-sandbox
```

GitHub Actions 在 push/PR 上运行上述 SwiftPM 与 Xcode 命令。GitHub Release `v1.1.2` 已发布，包含 App、CLI、动态库、许可证和独立更新 helper；Developer ID 签名、公证和完整第三方来源核查仍待完成。每次代码或修复完成后必须：跑测试、更新版本与变更日志、执行 `scripts/export-release.zsh`、提交并推送 `main`、创建版本 tag、发布 GitHub Release，并上传 zip 与 `.sha256`。

## 技术栈

Swift 6、SwiftUI/AppKit、AVFoundation、Combine，以及内置 arm64 LAME/mpg123 库。

## 目录与约定

- `VoiceConvert/Sources/`：应用、转换引擎、队列和 LAME bridge
- `VoiceConvertCore/`：Foundation-only SwiftPM 核心（字幕、扫描、配对、任务、设置模型）
- `VoiceConvertCLI/`：SwiftPM CLI，含本地音频后端并静态链接 arm64 LAME/mpg123
- `VoiceConvertTests/`、`VoiceConvertCore/Tests`、`VoiceConvertCLI/Tests`：测试
- `ThirdParty/`：头文件、库文件和许可证
- `scripts/export-release.zsh`：生成自包含发布压缩包并上传前生成 SHA-256
- `VoiceConvert.xcodeproj/`：唯一 Xcode 工程
- `build/`、`**/.build/`、`.zcode/` 和 Xcode 用户文件不提交
- 保持产品名“音声转换”、Bundle ID `com.voiceconvert.app`、arm64 和 macOS 26.0+ 约束

## 当前状态

Release `v1.1.2` 已发布并验证（tag、远端 CI 和 zip/checksum 均通过）。当前代码已接入 GitHub Releases 更新检查、SHA-256/压缩包校验、用户确认安装和独立临时 helper；本轮 `v1.1.3` 将只同步现役文档、发布流程和版本事实。Developer ID 签名、公证、完整第三方来源核查仍待完成。下一步候选：CLI 取消/重试/最近批次、三条工作流统一最近批次，以及为发布脚本加入自动 CI 资产构建。