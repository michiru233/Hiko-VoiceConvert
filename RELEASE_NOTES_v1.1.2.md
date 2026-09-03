# Hiko-VoiceConvert v1.1.2

## Highlights

- GitHub Releases update checks from the “音声转换” app menu and a background check at launch.
- User-confirmed downloads only; the app verifies the arm64 archive SHA-256, archive layout, Bundle ID, version, and ad-hoc code signature before installation.
- A standalone temporary installer helper waits for the app to exit, atomically replaces it, relaunches the new app, preserves the old app on failure, and cleans temporary files.

## Verification

- VoiceConvertCore: 73/73 tests passed, including offline update parsing and checksum tests.
- VoiceConvertCLI: 5/5 tests passed.
- Xcode Debug build: passed.
- Release archive includes `App/音声转换.app/Contents/Resources/Helpers/update-helper`.

## Requirements and limitations

- macOS 26.0 or newer, Apple Silicon arm64.
- The archive is ad-hoc signed, not Developer-ID signed or notarized. Gatekeeper may require manual approval.
