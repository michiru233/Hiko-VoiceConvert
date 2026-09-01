# Hiko-VoiceConvert

原生 macOS 音声处理工具，产品名为“音声转换”。它将常见音频批量转换为 MP3，并将 WebVTT 字幕转换为 UTF-8 LRC；配对模块可按安全主干名预览音频与字幕关系。

## 功能

- 音频转换：WAV、FLAC、AIFF、AIF、M4A → MP3
- 字幕转换：WebVTT → LRC，支持宽松/严格解析、HTML/karaoke 清洗和可选说话人前缀
- 配对处理：大小写不敏感的安全主干名匹配；支持 `track.mp3.vtt`、`track.flac.vtt` 等伴随字幕；歧义项不会自动配对
- 文件夹递归扫描，跳过隐藏项和符号链接目录，规范化路径去重并保留相对目录结构
- 音频队列支持并发、暂停、继续和取消；默认不覆盖已有输出
- 应用提供“音频转换”“字幕转换”“配对处理”三个平级模块和最近批次摘要

## 系统要求

- macOS 26.0 或更高版本
- Apple Silicon（arm64）Mac
- Xcode 26.6 或兼容的 Xcode 版本，用于构建

当前工程和随附的第三方二进制库均只提供 arm64 架构，不支持 Intel Mac 或 Universal 构建。

## 构建与测试

在项目根目录执行：

```bash
xcodebuild -project VoiceConvert.xcodeproj -scheme VoiceConvert -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO
xcodebuild -project VoiceConvert.xcodeproj -scheme VoiceConvert -configuration Debug -sdk macosx test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
swift test --package-path VoiceConvertCore --disable-sandbox
swift test --package-path VoiceConvertCLI --disable-sandbox
```

构建产物写入 `build/Debug` 或 `build/Release`，这些目录已被 Git 忽略。

## 使用方式

构建并运行 `音声转换.app` 后，可拖入文件或文件夹，或使用“添加输入”。音频输出默认写入 Music/音声库，字幕输出写在源文件旁；应用不会默认删除源文件，也不会覆盖已有输出。CLI 用法和退出码见 [VoiceConvertCLI/README.md](VoiceConvertCLI/README.md)。发布压缩包包含 App、CLI、运行库、许可证和帮助文档，详见 GitHub Releases。

当前 CLI 支持 `audio`、`subtitle` 和 `pair` 三个子命令。`audio` 使用仓库内 arm64 LAME/mpg123 静态库和 AVFoundation 执行真实 MP3 转换；`pair` 使用同一音频后端生成同目录同主干的 MP3/LRC。支持 `--output`、`--policy suffix|skip|overwrite`、`--yes`，`audio --check` 仍只做预检。命令输出、冲突保护和退出码见 [VoiceConvertCLI/README.md](VoiceConvertCLI/README.md)。

## 项目状态与限制

这是一个面向 Apple Silicon 的早期 v1.1.0 版本。当前工程配置为本机开发构建：未配置 Developer ID Application 签名，也未完成 notarization 和 stapling。直接分发前需要使用正式开发者账号重新签名并完成公证。

仓库中的许可证、头文件和构建所需的 LAME/mpg123 库位于 `ThirdParty/`。现有二进制来自本机 Homebrew bottle；目前无法从仓库记录确认精确的上游版本、完整下载来源或对应源码包。因此第三方二进制的再分发合规性仍待核查，不能将当前依赖描述为完全可复现的源码构建。

统一任务状态、输入快照、最近 30 批次持久化、设置导入导出、安全作用域书签、三语 String Catalog 和脱敏诊断报告已接入；GitHub Actions 扩展仍待完成。

## 第三方依赖

第三方版权和许可证文件位于 `ThirdParty/licenses/`，具体说明见 [NOTICE](NOTICE)。在重新分发应用或替换依赖前，请先完成对应许可证义务和源码获取条件的核查。

## 许可证

项目自有源码以 MIT 许可证发布，见 [LICENSE](LICENSE)。MIT 许可证不覆盖 LAME、mpg123 或其他第三方内容。
