# Hiko-VoiceConvert

原生 macOS 音频转换工具，产品名为“音声转换”。它使用 AVFoundation 读取音频，并通过内置的 LAME 编码器将常见音频文件批量转换为 MP3。

## 功能

- 支持 WAV、FLAC、AIFF 和 M4A 输入
- 支持拖放文件、选择文件夹并递归扫描
- 批量转换、并发队列、暂停与取消
- 默认使用 LAME V2 质量设置、保留双声道和源采样率
- 输出文件冲突保护，不会覆盖已有文件
- 可选在转换成功后删除源文件

## 系统要求

- macOS 26.0 或更高版本
- Apple Silicon（arm64）Mac
- Xcode 26.6 或兼容的 Xcode 版本，用于构建

当前工程和随附的第三方二进制库均只提供 arm64 架构，不支持 Intel Mac 或 Universal 构建。

## 构建与测试

在项目根目录执行：

```bash
xcodebuild \
  -project VoiceConvert.xcodeproj \
  -scheme VoiceConvert \
  -configuration Debug \
  -sdk macosx \
  build CODE_SIGNING_ALLOWED=NO
```

运行测试：

```bash
xcodebuild \
  -project VoiceConvert.xcodeproj \
  -scheme VoiceConvert \
  -configuration Debug \
  -sdk macosx \
  test CODE_SIGNING_ALLOWED=NO
```

构建产物写入 `build/Debug` 或 `build/Release`，这些目录已被 Git 忽略。

> 当前 GitHub 源码快照仍缺少 `ThirdParty/lib/` 下的 3 个依赖文件（见“项目状态与限制”），因此全新 checkout 目前不能独立完成构建。

## 使用方式

构建并运行 `音声转换.app` 后，将音频文件或文件夹拖入窗口，选择输出位置和编码质量，然后开始转换。应用不会默认删除源文件；只有显式启用该选项后，转换成功的源文件才会被删除。

## 项目状态与限制

这是一个面向 Apple Silicon 的早期版本。当前工程配置为本机开发构建：未配置 Developer ID Application 签名，也未完成 notarization 和 stapling。直接分发前需要使用正式开发者账号重新签名并完成公证。

仓库中的许可证和头文件位于 `ThirdParty/`；本机 Release 包还会嵌入 LAME 和 mpg123 动态库。当前 GitHub 源码快照只跟踪了 `libmp3lame.a`，缺少工程链接所需的 `libmp3lame.dylib`、`libmpg123.a` 和 `libmpg123.dylib`，所以 GitHub Actions 目前会在链接阶段失败。现有二进制来自本机 Homebrew bottle；目前无法从仓库记录确认精确的上游版本、完整下载来源或对应源码包。因此第三方二进制的再分发合规性和源码仓库的可复现构建仍待核查，不能将当前依赖描述为已完整纳入仓库。

自动化测试目前覆盖配置、递归扫描、输出路径与冲突保护、损坏输入，以及 WAV 转 MP3 的基本技术参数；并不等同于所有输入格式的完整兼容性测试。

## 第三方依赖

第三方版权和许可证文件位于 `ThirdParty/licenses/`，具体说明见 [NOTICE](NOTICE)。在重新分发应用或替换依赖前，请先完成对应许可证义务和源码获取条件的核查。

## 许可证

项目自有源码以 MIT 许可证发布，见 [LICENSE](LICENSE)。MIT 许可证不覆盖 LAME、mpg123 或其他第三方内容。
