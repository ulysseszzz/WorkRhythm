#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-1.1.0}"
DERIVED_DATA="${DERIVED_DATA_PATH:-${TMPDIR:-/tmp}/WorkRhythm-Release-DerivedData}"
OUTPUT_DIR="${1:-$ROOT/dist}"
APP="$DERIVED_DATA/Build/Products/Release/工位节奏.app"
ARCHIVE="$OUTPUT_DIR/WorkRhythm-v$VERSION-macOS-universal.zip"
CHECKSUM="$OUTPUT_DIR/WorkRhythm-v$VERSION-SHA256.txt"

mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA" "$ARCHIVE" "$CHECKSUM"

cd "$ROOT"
python3 Tools/generate_project.py
swift test --scratch-path "${TMPDIR:-/tmp}/WorkRhythm-release-tests"
xcodebuild \
  -project WorkRhythm.xcodeproj \
  -scheme WorkRhythm \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

codesign --verify --deep --strict "$APP"
test "$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)" = "$VERSION"
test "$(lipo -archs "$APP/Contents/MacOS/工位节奏")" = "x86_64 arm64" \
  || test "$(lipo -archs "$APP/Contents/MacOS/工位节奏")" = "arm64 x86_64"
codesign -dvv "$APP" 2>&1 | grep -q "flags=.*runtime"
if codesign -d --entitlements :- "$APP" 2>&1 | grep -q "get-task-allow"; then
  printf 'Release must not contain get-task-allow\n' >&2
  exit 1
fi

COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"
if unzip -Z1 "$ARCHIVE" | grep -q '^__MACOSX/'; then
  printf 'Release archive contains AppleDouble metadata\n' >&2
  exit 1
fi
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")")

printf 'Created %s\nCreated %s\n' "$ARCHIVE" "$CHECKSUM"
