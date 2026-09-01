#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.1.0}"
STAGING="$ROOT/build/release-staging"
DIST="$ROOT/build/Hiko-VoiceConvert-v${VERSION}-macos-arm64"
APP="$ROOT/build/Release/音声转换.app"
CLI="$ROOT/VoiceConvertCLI/.build/arm64-apple-macosx/release/voiceconvert"

rm -rf "$STAGING" "$DIST" "$DIST.zip" "$DIST.zip.sha256"
mkdir -p "$STAGING/App" "$STAGING/CLI" "$STAGING/ThirdParty/licenses" "$STAGING/Docs"

[[ -d "$APP" ]] || { print -u2 "Release App not found: $APP"; exit 1; }
[[ -x "$CLI" ]] || { print -u2 "Release CLI not found: $CLI"; exit 1; }

file "$APP/Contents/MacOS/音声转换" | grep -q 'arm64'
file "$CLI" | grep -q 'arm64'

cp -R "$APP" "$STAGING/App/"
cp "$CLI" "$STAGING/CLI/voiceconvert"
cp "$ROOT/ThirdParty/lib/libmp3lame.dylib" "$STAGING/App/音声转换.app/Contents/Frameworks/"
cp "$ROOT/ThirdParty/lib/libmpg123.dylib" "$STAGING/App/音声转换.app/Contents/Frameworks/"
cp "$ROOT/README.md" "$ROOT/VoiceConvertCLI/README.md" "$ROOT/NOTICE" "$ROOT/LICENSE" "$STAGING/Docs/"
cp "$ROOT/ThirdParty/licenses/"* "$STAGING/ThirdParty/licenses/"

cat > "$STAGING/README.txt" <<EOF
Hiko-VoiceConvert v${VERSION} macOS arm64

App: App/音声转换.app
CLI: CLI/voiceconvert

System requirement: macOS 26.0+, Apple Silicon arm64.
This archive is an unsigned development release and is not notarized.
Gatekeeper may require manual approval before opening the App.
Third-party license files are in ThirdParty/licenses/.
EOF

if find "$STAGING" \( -name '*.tmp' -o -name '.zcode' -o -name 'VoiceConvertTests.xctest' \) -print -quit | grep -q .; then
  print -u2 "Unexpected temporary or test artifact in staging"
  exit 1
fi

[[ -f "$STAGING/ThirdParty/licenses/LAME_COPYING" ]]
[[ -f "$STAGING/ThirdParty/licenses/LAME_LICENSE" ]]
[[ -f "$STAGING/ThirdParty/licenses/MPG123_COPYING" ]]
[[ -f "$STAGING/ThirdParty/licenses/MPG123_AUTHORS" ]]

mv "$STAGING" "$DIST"
(
  cd "$ROOT/build"
  /usr/bin/zip -X -q -r "$(basename "$DIST").zip" "$(basename "$DIST")"
)
shasum -a 256 "$DIST.zip" > "$DIST.zip.sha256"

ZIP_ENTRIES="$(unzip -Z1 "$DIST.zip")"
[[ "$ZIP_ENTRIES" == *"/App/"* ]]
[[ "$ZIP_ENTRIES" == *"/Contents/MacOS/"* ]]
[[ "$ZIP_ENTRIES" == *"/CLI/voiceconvert"* ]]
[[ "$ZIP_ENTRIES" == *"/ThirdParty/licenses/LAME_LICENSE"* ]]
if [[ "$ZIP_ENTRIES" == *"/build/"* || "$ZIP_ENTRIES" == *"/.zcode/"* || "$ZIP_ENTRIES" == *"VoiceConvertTests.xctest"* || "$ZIP_ENTRIES" == *".tmp"* || "$ZIP_ENTRIES" == *"__MACOSX/"* ]]; then
  print -u2 "Unexpected build, metadata, test, or temporary artifact in ZIP"
  exit 1
fi

print "Created: $DIST.zip"
print "Checksum: $DIST.zip.sha256"
