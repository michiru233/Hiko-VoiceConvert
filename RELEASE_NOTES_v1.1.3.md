# Hiko-VoiceConvert v1.1.3

## Maintenance release

- Synced `AGENTS.md`, README, CHANGELOG, PROGRESS, and BLOCKED to the verified v1.1.2 release state.
- Added the required release closeout workflow to project rules: test, version, package, commit, push, tag, GitHub Release, and post-upload checksum verification.
- No conversion behavior changed from v1.1.2.

## Verification

- VoiceConvertCore: 73/73 tests passed.
- VoiceConvertCLI: 5/5 tests passed.
- Xcode Debug build and XCTest passed.
- Release archive includes the standalone update helper, App, CLI, runtime libraries, licenses, and SHA-256 checksum.

## Requirements and limitations

- macOS 26.0 or newer, Apple Silicon arm64.
- The archive is ad-hoc signed, not Developer-ID signed or notarized. Gatekeeper may require manual approval.
