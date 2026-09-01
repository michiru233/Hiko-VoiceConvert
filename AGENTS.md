# Hiko-VoiceConvert 项目规则

## 项目定位

Hiko-VoiceConvert 是原生 macOS SwiftUI 音频转换工具，产品名为“音声转换”，将 WAV、FLAC、AIFF 和 M4A 批量转换为 MP3。

## 构建与测试

在项目根目录执行：

```bash
xcodebuild -project VoiceConvert.xcodeproj -scheme VoiceConvert -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO
xcodebuild -project VoiceConvert.xcodeproj -scheme VoiceConvert -configuration Debug -sdk macosx test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

当前 GitHub 源码已包含 3 个 `ThirdParty/lib` 文件，本机 Release 构建和 ad hoc 签名验证通过，GitHub Release `v1.0.0` 已发布。Developer ID 签名、公证和完整第三方来源核查仍待完成。

## 技术栈

Swift 5、SwiftUI/AppKit、AVFoundation、Combine，以及内置 arm64 LAME/mpg123 库。

## 目录与约定

- `VoiceConvert/Sources/`：应用、转换引擎、队列和 LAME bridge
- `VoiceConvertTests/`：XCTest
- `ThirdParty/`：头文件、库文件和许可证
- `VoiceConvert.xcodeproj/`：唯一 Xcode 工程
- `build/`、`.zcode/` 和 Xcode 用户文件不提交
- 保持产品名“音声转换”、Bundle ID `com.voiceconvert.app`、arm64 和 macOS 26.0+ 约束

## 当前状态

本地 Release 构建和 ad hoc 签名验证通过，GitHub Release `v1.0.0` 已发布。Developer ID 签名、公证、完整第三方来源核查，以及将缺失库纳入源码仓库仍待完成。