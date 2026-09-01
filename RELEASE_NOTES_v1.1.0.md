# Hiko-VoiceConvert v1.1.0

## Highlights

- Three equal macOS workflows: audio conversion, WebVTT to LRC, and audio/subtitle pairing.
- Real AVFoundation and LAME-based MP3 conversion in both the App and CLI.
- Pairing creates same-directory MP3/LRC outputs with shared stems and parent/child task status.
- Conflict policies: suffix, skip, and overwrite with explicit confirmation.
- Settings panel with security-scoped output-directory bookmarks, import/export, three-language localization, license references, and redacted diagnostic JSON.
- CLI commands: `audio`, `subtitle`, `pair`, plus legacy `--convert` compatibility.

## Verification

- VoiceConvertCore: 66/66 tests passed.
- VoiceConvertCLI: 5/5 tests passed.
- Xcode XCTest: 12/12 tests passed.
- Xcode arm64 Debug and Release builds passed.
- Real WAV to MP3 and paired MP3/LRC fixtures passed.
- Conflict, malformed input, unreadable input, and missing dynamic-library red/green checks were recorded.

## Included archive

`Hiko-VoiceConvert-v1.1.0-macos-arm64.zip` contains:

- `音声转换.app` and its runtime dynamic libraries.
- `CLI/voiceconvert`.
- LAME/mpg123 license files, `NOTICE`, `LICENSE`, and usage documentation.
- SHA-256 checksum is provided separately.

## Requirements and limitations

- macOS 26.0 or newer.
- Apple Silicon arm64.
- This archive is an unsigned development release and is not notarized. Gatekeeper may require manual approval.
- The bundled third-party binaries came from a local Homebrew bottle; exact upstream provenance and redistribution review remain outstanding.
- CLI cancellation/retry/recent-history process-level features and GitHub-hosted CI run evidence remain follow-up work.
