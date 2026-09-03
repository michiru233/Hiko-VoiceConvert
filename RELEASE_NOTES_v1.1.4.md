# Hiko-VoiceConvert v1.1.4

## Maintenance release

- Added `ThirdParty/PROVENANCE.md` with verified LAME 4.0 and mpg123 1.33.7 source URLs, Homebrew formula revision, bottle checksums, and repository artifact SHA-256 values.
- Updated NOTICE and BLOCKED to distinguish resolved source traceability from the remaining LGPL static-linking redistribution decision.

## Verification

- VoiceConvertCore: 73/73 tests passed.
- VoiceConvertCLI: 5/5 tests passed.
- Xcode Debug build and XCTest passed.

## Requirements and limitations

- macOS 26.0 or newer, Apple Silicon arm64.
- The archive is ad-hoc signed, not Developer-ID signed or notarized. Gatekeeper may require manual approval.
- CLI static linking of LGPL libraries remains subject to project-owner or legal review for redistribution obligations.
