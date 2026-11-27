#!/usr/bin/env bash
set -e

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SOURCE_DIR"

APP_NAME="ai-type-agent"
VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//' | cut -d '+' -f1)"
DIST_DIR="$SOURCE_DIR/dist"
APK_OUT="$DIST_DIR/${APP_NAME}_${VERSION}_android.apk"

echo "=== BAT DAU BIEN DICH FILE APK ANDROID ($VERSION) ==="

FLUTTER_BIN="$(which flutter 2>/dev/null || echo '/snap/bin/flutter')"
echo "1. Dang bien dich ban release Android APK bang $FLUTTER_BIN..."
"$FLUTTER_BIN" build apk --release

mkdir -p "$DIST_DIR"
cp -f "$SOURCE_DIR/build/app/outputs/flutter-apk/app-release.apk" "$APK_OUT"

echo "=== HOAN TAT TAO FILE APK ==="
ls -lh "$APK_OUT"
