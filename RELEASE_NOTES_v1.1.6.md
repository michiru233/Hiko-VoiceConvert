# Hiko-VoiceConvert v1.1.6

## Automation fix

- Replaced the release workflow's version parsing dependency with built-in macOS tools so the GitHub runner can execute the tag/version gate without extra packages.
- This tag revalidates automatic testing, packaging, checksum creation, and GitHub Release publishing.

## Requirements and limitations

- macOS 26.0 or newer, Apple Silicon arm64.
- The archive is ad-hoc signed, not Developer-ID signed or notarized. Gatekeeper may require manual approval.
