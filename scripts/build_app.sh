#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="WorkLog"
APP_DIR="$ROOT/dist/$APP_NAME.app"

swift build --build-system native -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build --build-system native -c "$CONFIG" --product "$APP_NAME" --show-bin-path | tail -1)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/App/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=1 "$APP_DIR"

echo "Built: $APP_DIR"
