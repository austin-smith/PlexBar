#!/usr/bin/env bash
set -euo pipefail

MODE="run"
ENABLE_MOCK_RUNTIME=0
APP_NAME="PlexBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PlexBar.xcodeproj"
SCHEME="PlexBar"

if [[ -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env.local"
  set +a
fi

BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
APP_MARKETING_VERSION="${APP_MARKETING_VERSION:-}"
APP_BUILD_VERSION="${APP_BUILD_VERSION:-}"
SPARKLE_APPCAST_URL="${SPARKLE_APPCAST_URL:-}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
CODE_SIGN_KEYCHAIN="${CODE_SIGN_KEYCHAIN:-}"
DERIVED_DATA_DIR="${PLEXBAR_DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
SOURCE_PACKAGES_DIR="${PLEXBAR_SOURCE_PACKAGES_PATH:-$ROOT_DIR/.build/SourcePackages}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

usage() {
  echo "usage: $0 [--mock] [build|run|debug|logs|telemetry|verify]" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mock)
        ENABLE_MOCK_RUNTIME=1
        ;;
      build|run|debug|logs|telemetry|verify|--build|--debug|--logs|--telemetry|--verify)
        MODE="${1#--}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        exit 2
        ;;
    esac
    shift
  done
}

parse_args "$@"

case "$BUILD_CONFIGURATION" in
  debug|Debug)
    XCODE_CONFIGURATION="Debug"
    ;;
  release|Release)
    XCODE_CONFIGURATION="Release"
    ;;
  *)
    echo "BUILD_CONFIGURATION must be 'debug' or 'release', received '$BUILD_CONFIGURATION'." >&2
    exit 2
    ;;
esac

if [[ "$XCODE_CONFIGURATION" == "Release" && (-z "$SPARKLE_APPCAST_URL" || -z "$SPARKLE_PUBLIC_KEY") ]]; then
  echo "Missing required Sparkle build metadata: SPARKLE_APPCAST_URL and SPARKLE_PUBLIC_KEY." >&2
  exit 2
fi

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$XCODE_CONFIGURATION"
  -destination "platform=macOS,arch=$(uname -m)"
  -derivedDataPath "$DERIVED_DATA_DIR"
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR"
  -onlyUsePackageVersionsFromResolvedFile
)

BUILD_SETTINGS=(
  "SPARKLE_APPCAST_URL=$SPARKLE_APPCAST_URL"
  "SPARKLE_PUBLIC_KEY=$SPARKLE_PUBLIC_KEY"
)

if [[ -n "$APP_MARKETING_VERSION" ]]; then
  BUILD_SETTINGS+=("MARKETING_VERSION=$APP_MARKETING_VERSION")
fi

if [[ -n "$APP_BUILD_VERSION" ]]; then
  BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$APP_BUILD_VERSION")
fi

if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
  if [[ -z "$APPLE_TEAM_ID" ]]; then
    echo "APPLE_TEAM_ID is required when CODE_SIGN_IDENTITY is configured." >&2
    exit 2
  fi

  BUILD_SETTINGS+=(
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY"
    "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
  )

  if [[ -n "$CODE_SIGN_KEYCHAIN" ]]; then
    BUILD_SETTINGS+=("OTHER_CODE_SIGN_FLAGS=--timestamp --keychain $CODE_SIGN_KEYCHAIN")
  else
    BUILD_SETTINGS+=("OTHER_CODE_SIGN_FLAGS=--timestamp")
  fi
elif [[ -n "$APPLE_TEAM_ID" ]]; then
  BUILD_SETTINGS+=("DEVELOPMENT_TEAM=$APPLE_TEAM_ID")
else
  BUILD_SETTINGS+=(
    "CODE_SIGN_STYLE=Manual"
    "CODE_SIGN_IDENTITY=-"
  )
fi

xcodebuild "${XCODEBUILD_ARGS[@]}" "${BUILD_SETTINGS[@]}" build

BUILT_APP="$DERIVED_DATA_DIR/Build/Products/$XCODE_CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Xcode did not produce the expected app at $BUILT_APP." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$DIST_DIR"
ditto "$BUILT_APP" "$APP_BUNDLE"

open_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true

  if [[ "$ENABLE_MOCK_RUNTIME" -eq 1 ]]; then
    /usr/bin/open -n "$APP_BUNDLE" --args --mock
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

verify_app_bundle() {
  local app_binary="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
  local info_plist="$APP_BUNDLE/Contents/Info.plist"
  local sparkle_framework="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  local bundle_id
  local app_architectures
  local plist_minimum_version
  local binary_minimum_version
  local signature_details
  local signed_entitlements

  [[ -x "$app_binary" ]] || { echo "Missing app executable at $app_binary." >&2; exit 1; }
  [[ -f "$info_plist" ]] || { echo "Missing Info.plist at $info_plist." >&2; exit 1; }
  [[ -d "$sparkle_framework" ]] || { echo "Missing Sparkle framework at $sparkle_framework." >&2; exit 1; }
  [[ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]] || { echo "Missing compiled app icon." >&2; exit 1; }
  [[ -f "$APP_BUNDLE/Contents/Resources/MenuBarIcon.tiff" ]] || { echo "Missing menu-bar icon." >&2; exit 1; }

  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  plutil -lint "$info_plist" >/dev/null

  if [[ "$XCODE_CONFIGURATION" == "Release" ]]; then
    app_architectures="$(lipo -archs "$app_binary")"
    if [[ " $app_architectures " != *" arm64 "* || " $app_architectures " != *" x86_64 "* ]]; then
      echo "The Release app must be universal (arm64 and x86_64); found: $app_architectures" >&2
      exit 1
    fi

    signature_details="$(codesign -dvv "$APP_BUNDLE" 2>&1)"
    if [[ "$signature_details" != *"runtime"* ]]; then
      echo "The Release app is missing hardened-runtime signing." >&2
      exit 1
    fi

    signed_entitlements="$(codesign -d --entitlements - "$APP_BUNDLE" 2>/dev/null)"
    if [[ "$signed_entitlements" == *"com.apple.security.get-task-allow"* ]]; then
      echo "The Release app must not contain the debugger entitlement." >&2
      exit 1
    fi
  fi

  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
  plist_minimum_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")"
  binary_minimum_version="$(
    otool -l "$app_binary" |
      awk '
        $1 == "cmd" && $2 == "LC_BUILD_VERSION" { in_build_version = 1; next }
        in_build_version && $1 == "minos" { print $2; exit }
      '
  )"

  if [[ "$bundle_id" != "com.crapshack.PlexBar" ]]; then
    echo "Unexpected bundle identifier: $bundle_id" >&2
    exit 1
  fi
  if [[ "$plist_minimum_version" != "26.0" ]]; then
    echo "Unexpected Info.plist minimum system version: $plist_minimum_version" >&2
    exit 1
  fi
  if [[ "$binary_minimum_version" != "26.0" ]]; then
    echo "Unexpected Mach-O minimum system version: $binary_minimum_version" >&2
    exit 1
  fi

  printf 'Verified app bundle at %s\n' "$APP_BUNDLE"
}

case "$MODE" in
  build)
    printf 'Built app bundle at %s\n' "$APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  debug)
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    if [[ "$ENABLE_MOCK_RUNTIME" -eq 1 ]]; then
      lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" --mock
    else
      lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    fi
    ;;
  logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.crapshack.PlexBar"'
    ;;
  verify)
    verify_app_bundle
    ;;
esac
