# Hiko-VoiceConvert v1.1.5

## Automation release

- Added a tag-triggered GitHub Actions workflow that validates version consistency, runs Core/CLI/Xcode tests, builds the archive, verifies its SHA-256 and signatures, then creates the GitHub Release with the zip and checksum.
- No Apple Developer credentials are required for the current ad-hoc-signed distribution workflow.

## Verification

- VoiceConvertCore: 73/73 tests passed.
- VoiceConvertCLI: 5/5 tests passed.
- Xcode Debug build and XCTest passed.
- This tag is the end-to-end validation of automatic packaging and GitHub Release publishing.

## Requirements and limitations

- macOS 26.0 or newer, Apple Silicon arm64.
- The archive is ad-hoc signed, not Developer-ID signed or notarized. Gatekeeper may require manual approval.
