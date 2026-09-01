# 变更日志

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
