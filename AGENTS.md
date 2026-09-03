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

GitHub Actions 在 push/PR 上运行上述 SwiftPM 与 Xcode 命令。GitHub Release `v1.1.0` 已发布；本地 `v1.1.1` 进度反馈更新待推送。Developer ID 签名、公证和完整第三方来源核查仍待完成。

## 技术栈

Swift 6、SwiftUI/AppKit、AVFoundation、Combine，以及内置 arm64 LAME/mpg123 库。

## 目录与约定

- `VoiceConvert/Sources/`：应用、转换引擎、队列和 LAME bridge
- `VoiceConvertCore/`：Foundation-only SwiftPM 核心（字幕、扫描、配对、任务、设置模型）
- `VoiceConvertCLI/`：SwiftPM CLI，含本地音频后端并静态链接 arm64 LAME/mpg123
- `VoiceConvertTests/`、`VoiceConvertCore/Tests`、`VoiceConvertCLI/Tests`：测试
- `ThirdParty/`：头文件、库文件和许可证
- `scripts/export-release.zsh`：生成自包含发布压缩包
- `VoiceConvert.xcodeproj/`：唯一 Xcode 工程
- `build/`、`**/.build/`、`.zcode/` 和 Xcode 用户文件不提交
- 保持产品名“音声转换”、Bundle ID `com.voiceconvert.app`、arm64 和 macOS 26.0+ 约束

## 当前状态

Release `v1.1.0` 已发布并验证（PR #1、tag v1.1.0、远程 CI 全绿）。当前 `v1.1.1` 发布准备正在进行；Developer ID 签名、公证、完整第三方来源核查仍待完成。下一步候选：GUI 自包含导出目录、CLI 取消/重试/最近批次、三条工作流统一最近批次记录。
