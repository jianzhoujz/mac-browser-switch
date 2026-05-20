#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_VERSION="${APP_VERSION:-${VERSION:-0.1.0}}"
APP_BUILD="${APP_BUILD:-$APP_VERSION}"
APP_BUILD_TIME="${APP_BUILD_TIME:-$(date '+%Y-%m-%d %H:%M:%S %z')}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-12.0}"

APP_NAME="BrowserSwitch"
DISPLAY_NAME="BrowserSwitch"
BUNDLE_ID="local.mac-browser-switch"

APP="$ROOT/build/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"
RESOURCES="$APP/Contents/Resources"
SOURCE_RESOURCES="$ROOT/Resources"
APP_ICON="$SOURCE_RESOURCES/AppIcon.icns"

rm -rf "$ROOT/build"
mkdir -p "$ROOT/build"
TMP_DIR="$(mktemp -d "$ROOT/build/$APP_NAME.XXXXXX")"
SLICE_BINS=()

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$APP/Contents/MacOS" "$RESOURCES"

compile_slice() {
  local arch="$1"
  local output="$TMP_DIR/$APP_NAME-$arch"

  swiftc \
    -target "$arch-apple-macosx$DEPLOYMENT_TARGET" \
    -O \
    -framework AppKit \
    "$ROOT/Sources/BrowserSwitch.swift" \
    -o "$output"

  SLICE_BINS+=("$output")
}

compile_slice arm64
compile_slice x86_64
lipo -create "${SLICE_BINS[@]}" -output "$BIN"
chmod +x "$BIN"

# Auto-generate the icon on first build (or when REGENERATE_APP_ICON=1).
# The .icns is small and stable — it's committed to the repo after the first
# generation, so subsequent builds skip this step.
if [[ ! -f "$APP_ICON" || "${REGENERATE_APP_ICON:-0}" == "1" ]]; then
  mkdir -p "$SOURCE_RESOURCES"
  ICONSET="$ROOT/build/AppIcon.iconset"
  swift "$ROOT/tools/make_app_icon.swift" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$APP_ICON"
  rm -rf "$ICONSET"
fi

cp "$APP_ICON" "$RESOURCES/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>BuildTime</key>
  <string>$APP_BUILD_TIME</string>
  <key>LSMinimumSystemVersion</key>
  <string>$DEPLOYMENT_TARGET</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "$APP"
