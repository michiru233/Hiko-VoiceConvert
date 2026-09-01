# 阻塞项

- Developer ID Application 签名、公证和 stapling 未执行：重要性高，是公开分发和 Gatekeeper 信任的发布门槛。当前环境 `security find-identity -v -p codesigning` 返回 `0 valid identities found`，`xcrun notarytool history` 报 `Must provide credentials`。需要项目所有者提供 Developer ID 证书、团队/钥匙串权限和 notarization 凭据后执行。
- 第三方 `ThirdParty/lib` 二进制来自本机 Homebrew bottle；重要性高，关系到许可证履行、可复现构建和再分发合规。需要项目所有者确认精确 Homebrew formula/version、下载来源、对应源码包和许可证义务，或授权一次完整上游核查。
- `VoiceConvertCore` 仍保持 Foundation-only，不包含音频编码后端；CLI 已在自身 `VoiceConvertAudioBackend` target 中静态链接仓库内 arm64 LAME/mpg123，因此 `audio`/`pair` 可实际执行。重要性中，当前架构是刻意隔离而非故障。
- App 的安全作用域书签、设置导入导出、三语 String Catalog、许可证展示和脱敏诊断报告已实现并通过 Core/XCTest 验证。
- GitHub Actions workflow 已配置并已由 tag `v1.1.0` run `33501853200` 和发布后 `main` run `33502128860` 验证通过：SwiftPM Core/CLI/CLI build 和 Xcode App/XCTest 均为绿色。
- GUI 自包含导出目录（CLI、动态库、许可证和帮助文档）尚未实现；重要性中高，公开分发前需要。该项可由开发工作完成，不需要 Apple 凭据。
- CLI 取消、重试、最近批次的独立进程级证据仍未补齐；重要性中，Core/App 已覆盖对应状态模型和批次保存。若要求 CLI 也具备完整恢复历史，需要增加 CLI 参数和持久化协议。
- 反向验收：不可读输入与动态库缺失已完成红→绿验证。不可读 WAV 权限 `000` 时 CLI `audio` 返回 1 并输出 `FAILED`，恢复 `0644` 后返回 0 并生成 MP3；移走 App bundle 的 `libmp3lame.dylib` 时 dyld 返回 134 并报告 `Library not loaded`，恢复后加载跟踪无缺失错误。恢复后的 GUI 进程以受控终止码 137 结束，不作为业务成功码。

## 已知非阻塞备注

Xcode 构建日志包含 AppIntents 元数据跳过和第三方动态库 Copy/签名相关 warning，但没有动态库复制步骤错误；Debug build 与 XCTest 均已通过。SwiftPM 测试输出中的兼容层摘要不代表实际结果，实际 Core 测试结果以 Swift Testing 汇总为准。
