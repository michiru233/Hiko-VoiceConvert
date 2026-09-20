# Hiko-VoiceConvert v1.1.8

## Bug fix: converted MP3 duration no longer matches the source

- Fixed converted MP3 files reporting a playback duration that did not match the source audio.
- Root cause: LAME reserves an empty MP3 frame at the start of the stream and expects the caller to replace it with the final VBR/Xing tag frame after encoding. That back-fill was missing, so players had no frame count and fell back to estimating duration from the first frame bitrate — a 10.000 s source displayed as 7.31 s.
- Both conversion paths now write the tag frame: the App (`LameEncoder.lametagFrame()` + `ConversionEngine`) and the CLI (`CLIAudioConverter`).
- Audio payload is unchanged: byte-for-byte identical after the leading frame, identical file size, decoded samples preserved. Only the leading 417-byte placeholder frame changes.
- Regression tests added for both targets, each verified to fail without the fix: `testOutputCarriesVBRHeaderSoPlaybackDurationMatchesSource` (XCTest and swift-testing).
- Verified across 44.1/48/32 kHz, mono and stereo, and 0.5–10 s inputs.

## Packaging fix

- `scripts/export-release.zsh` hard-coded `.build/arm64-apple-macosx/release`, which on SwiftPM layouts that output to `.build/out/Products/Release` silently packaged a stale `voiceconvert` from an earlier build. The script now builds the CLI and resolves the real output directory via `swift build --show-bin-path`.

## Verification

- VoiceConvertCore: 73/73 tests passed.
- VoiceConvertCLI: 6/6 tests passed.
- Xcode Debug build and XCTest: 13/13 tests passed.
- Player-reported duration matches the source across all tested sample rates and channel counts; VBR header present in every output.
- The packaged archive was unpacked and its bundled CLI re-tested end to end, confirming the fix is present in the released binary.

## Requirements and limitations

- macOS 26.0 or newer, Apple Silicon arm64.
- The archive is ad-hoc signed, not Developer-ID signed or notarized. Gatekeeper may require manual approval.
- CLI static linking of LGPL libraries remains subject to project-owner or legal review for redistribution obligations.
