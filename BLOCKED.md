# 阻塞项

- Developer ID Application 签名、公证和 stapling 未执行：重要性高，是公开分发和 Gatekeeper 信任的发布门槛。当前环境 `security find-identity -v -p codesigning` 返回 `0 valid identities found`，`xcrun notarytool history` 报 `Must provide credentials`。需要项目所有者提供 Developer ID 证书、团队/钥匙串权限和 notarization 凭据后执行。
- 第三方来源已可追溯：LAME 4.0 与 mpg123 1.33.7 的 Homebrew formula commit、上游源码、bottle 和仓库工件 SHA-256 已记录在 `ThirdParty/PROVENANCE.md`。但 CLI 静态链接 LGPL 库的对象文件/可重链接义务仍需要项目所有者或法律顾问确认；在裁定前不能宣称公开再分发完全合规。
- `VoiceConvertCore` 仍保持 Foundation-only，不包含音频编码后端；CLI 已在自身 `VoiceConvertAudioBackend` target 中静态链接仓库内 arm64 LAME/mpg123，因此 `audio`/`pair` 可实际执行。重要性中，当前架构是刻意隔离而非故障。
- CLI 取消、重试、最近批次的独立进程级证据仍未补齐；重要性中，Core/App 已覆盖对应状态模型和批次保存。若要求 CLI 也具备完整恢复历史，需要增加 CLI 参数和持久化协议。
- GitHub Actions 当前运行测试和 CLI 构建，但不会自动生成或上传 Release 资产；公开发布仍需在本机执行 `scripts/export-release.zsh` 后手动上传 zip 与 `.sha256`。

## 已知非阻塞备注

Xcode 构建日志包含 AppIntents 元数据跳过和第三方动态库 Copy/签名相关 warning，但没有动态库复制步骤错误；Debug build 与 XCTest 均已通过。SwiftPM 测试输出中的兼容层摘要不代表实际结果，实际测试结果以各自汇总为准。
