#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PlexBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}DMG.XXXXXX")"
DMG_BACKGROUND_PATH="$ROOT_DIR/.github/release-assets/background.png"
OUTPUT_DMG="${1:-$DIST_DIR/$APP_NAME.dmg}"

usage() {
  cat <<EOF
usage: $0 [output.dmg]
EOF
}

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

"$ROOT_DIR/script/build_and_run.sh" build

if [[ ! -f "$DMG_BACKGROUND_PATH" ]]; then
  echo "DMG background image not found at $DMG_BACKGROUND_PATH." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

create-dmg \
  --volname "$APP_NAME" \
  --window-size 660 420 \
  --background "$DMG_BACKGROUND_PATH" \
  --icon-size 128 \
  --text-size 13 \
  --icon "$APP_NAME.app" 180 165 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 480 165 \
  "$OUTPUT_DMG" \
  "$STAGING_DIR"

printf 'Created DMG at %s\n' "$OUTPUT_DMG"
