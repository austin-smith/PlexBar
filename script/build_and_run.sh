#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PlexBar"
BUNDLE_ID="com.crapshack.PlexBar"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_NAME="PlexBarAppIcon"
APP_ICON_SOURCE="$ROOT_DIR/$APP_ICON_NAME.icon"
ACTOOL="$(xcrun --find actool)"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -d "$APP_ICON_SOURCE" ]]; then
  ASSET_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/PlexBarAppIcon.XXXXXX")"
  ASSET_CATALOG="$ASSET_WORK_DIR/PlexBarAssets.xcassets"
  ASSET_OUTPUT="$ASSET_WORK_DIR/output"
  ASSET_INFO_PLIST="$ASSET_WORK_DIR/icon-info.plist"
  cleanup_icon_workdir() {
    rm -rf "$ASSET_WORK_DIR"
  }
  trap cleanup_icon_workdir EXIT

  mkdir -p "$ASSET_CATALOG" "$ASSET_OUTPUT"
  printf '{"info":{"author":"xcode","version":1}}\n' > "$ASSET_CATALOG/Contents.json"

  "$ACTOOL" \
    "$ASSET_CATALOG" \
    "$APP_ICON_SOURCE" \
    --compile "$ASSET_OUTPUT" \
    --output-format human-readable-text \
    --notices \
    --warnings \
    --output-partial-info-plist "$ASSET_INFO_PLIST" \
    --app-icon "$APP_ICON_NAME" \
    --target-device mac \
    --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
    --platform macosx \
    --bundle-identifier "$BUNDLE_ID"

  if [[ ! -f "$ASSET_OUTPUT/Assets.car" || ! -f "$ASSET_OUTPUT/$APP_ICON_NAME.icns" ]]; then
    echo "actool did not produce the expected app icon outputs." >&2
    exit 1
  fi

  cp "$ASSET_OUTPUT/Assets.car" "$APP_RESOURCES/Assets.car"
  cp "$ASSET_OUTPUT/$APP_ICON_NAME.icns" "$APP_RESOURCES/$APP_ICON_NAME.icns"
  /usr/libexec/PlistBuddy -c "Merge $ASSET_INFO_PLIST" "$INFO_PLIST"

  trap - EXIT
  cleanup_icon_workdir
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
