#!/usr/bin/env bash
# Builds the v2 runtime, archives and notarizes Detach, creates a Sparkle-signed
# DMG, and optionally publishes it to the Supabase updates bucket.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="Detach"
SCHEME="lazzy"
PROJECT_FILE="$PROJECT_ROOT/detach.xcodeproj"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
UPDATE_BASE_URL="${DETACH_UPDATE_BASE_URL:-https://qymrzmmsroxkteaxbgoo.supabase.co/storage/v1/object/public/updates}"
SUPABASE_URL="${SUPABASE_URL:-https://qymrzmmsroxkteaxbgoo.supabase.co}"
SUPABASE_UPDATES_BUCKET="${SUPABASE_UPDATES_BUCKET:-updates}"

VERSION=""
BUILD=""
OUTPUT_DIR=""
NOTARY_PROFILE="${DETACH_NOTARY_PROFILE:-}"
NOTARY_KEY_PATH="${APPLE_NOTARY_KEY_PATH:-}"
NOTARY_KEY_ID="${APPLE_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${APPLE_NOTARY_ISSUER_ID:-}"
SPARKLE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-}"
PUBLISH=false
SKIP_NOTARIZATION=false

fail() {
  echo "error: $*" >&2
  exit 1
}

note() {
  echo "\n==> $*"
}

require_command() {
  command -v "$1" >/dev/null || fail "Required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh --version 1.3.4 --build 8 [options]

Required:
  --version VERSION              User-visible version, for example 1.3.4
  --build BUILD                  Increasing Sparkle build number, for example 8

Options:
  --notary-profile NAME          Local notarytool keychain profile
  --notary-key PATH              App Store Connect API key (.p8) for notarization
  --notary-key-id ID             App Store Connect API key ID
  --notary-issuer-id ID          App Store Connect issuer ID
  --sparkle-key-file PATH        Sparkle EdDSA private key file
  --publish                      Upload the DMG and appcast to Supabase
  --skip-notarization            Local test only; cannot be combined with --publish
  --output PATH                  A new folder for release artifacts
  -h, --help                     Show this help

Secrets are read from environment variables when flags are omitted:
  DETACH_NOTARY_PROFILE, APPLE_NOTARY_KEY_PATH, APPLE_NOTARY_KEY_ID,
  APPLE_NOTARY_ISSUER_ID, SPARKLE_PRIVATE_KEY_FILE, SPARKLE_PRIVATE_KEY,
  SUPABASE_SERVICE_ROLE_KEY.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="$2"; shift 2 ;;
    --notary-key) NOTARY_KEY_PATH="$2"; shift 2 ;;
    --notary-key-id) NOTARY_KEY_ID="$2"; shift 2 ;;
    --notary-issuer-id) NOTARY_ISSUER_ID="$2"; shift 2 ;;
    --sparkle-key-file) SPARKLE_KEY_FILE="$2"; shift 2 ;;
    --publish) PUBLISH=true; shift ;;
    --skip-notarization) SKIP_NOTARIZATION=true; shift ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail "--version must look like 1.3.4"
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "--build must be an integer"
if [[ "$SKIP_NOTARIZATION" == true && "$PUBLISH" == true ]]; then
  fail "Refusing to publish an unnotarized release"
fi

OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/dist/release-$VERSION-$BUILD-$(date +%Y%m%d-%H%M%S)}"
[[ ! -e "$OUTPUT_DIR" ]] || fail "Output already exists: $OUTPUT_DIR (choose --output instead)"

require_command bun
require_command xcodebuild
require_command xcrun
require_command hdiutil
require_command ditto
require_command curl
require_command codesign

mkdir -p "$OUTPUT_DIR"
DERIVED_DATA="$OUTPUT_DIR/DerivedData"
ARCHIVE_PATH="$OUTPUT_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$OUTPUT_DIR/export"
STAGING_PATH="$OUTPUT_DIR/staging/$APP_NAME"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
APPCAST_WORKDIR="$OUTPUT_DIR/appcast-work"
APPCAST_PATH="$OUTPUT_DIR/appcast.xml"

note "Building the v2 Detach runtime"
(
  cd "$PROJECT_ROOT/server-v2"
  bun install --frozen-lockfile
  bun run build
)
ditto "$PROJECT_ROOT/server-v2/detach-runtime" "$PROJECT_ROOT/lazzy/detach-runtime"
RUNTIME_HASHES="$(shasum -a 256 "$PROJECT_ROOT/server-v2/detach-runtime" "$PROJECT_ROOT/lazzy/detach-runtime" | awk '{print $1}' | uniq)"
[[ "$(printf '%s\n' "$RUNTIME_HASHES" | wc -l | tr -d ' ')" == "1" ]] || fail "The bundled v2 runtime does not match the build output"

note "Archiving $APP_NAME $VERSION ($BUILD)"
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive

note "Exporting the Developer ID signed app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH"

APP_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$APP_PATH" ]] || fail "Xcode export did not produce an app"
codesign --deep --strict --verify --verbose=2 "$APP_PATH"

ARCHIVED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
[[ "$ARCHIVED_VERSION" == "$VERSION" ]] || fail "Exported version is $ARCHIVED_VERSION, expected $VERSION"
[[ "$ARCHIVED_BUILD" == "$BUILD" ]] || fail "Exported build is $ARCHIVED_BUILD, expected $BUILD"

if [[ "$SKIP_NOTARIZATION" == false ]]; then
  note "Creating the notarization archive"
  NOTARIZATION_ZIP="$OUTPUT_DIR/$APP_NAME-notarize.zip"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARIZATION_ZIP"

  note "Submitting the signed app archive to Apple for notarization"
  if [[ -n "$NOTARY_KEY_PATH" && -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" ]]; then
    xcrun notarytool submit "$NOTARIZATION_ZIP" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  elif [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$NOTARIZATION_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    fail "Provide --notary-profile or the App Store Connect API key options"
  fi
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
fi

note "Creating a DMG"
mkdir -p "$STAGING_PATH"
ditto "$APP_PATH" "$STAGING_PATH/$APP_NAME.app"

# Check if create-dmg is available for a styled, professional DMG window
if command -v create-dmg >/dev/null 2>&1; then
  rm -f "$DMG_PATH"
  create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --text-size 13 \
    --icon "$APP_NAME.app" 180 170 \
    --app-drop-link 480 170 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$STAGING_PATH"
else
  ln -s /Applications "$STAGING_PATH/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_PATH" -ov -format UDZO "$DMG_PATH"
fi

note "Generating the Sparkle appcast"
SPARKLE_TOOL="$(find "$DERIVED_DATA/SourcePackages/artifacts" -type f -path '*/Sparkle/bin/generate_appcast' -print -quit 2>/dev/null || true)"
[[ -n "$SPARKLE_TOOL" && -x "$SPARKLE_TOOL" ]] || fail "Sparkle generate_appcast tool was not resolved from Xcode's package artifacts"
mkdir -p "$APPCAST_WORKDIR"
curl --fail --silent --show-error "$UPDATE_BASE_URL/appcast.xml" -o "$APPCAST_WORKDIR/appcast.xml" || echo "No existing appcast found; creating a new feed."
ditto "$DMG_PATH" "$APPCAST_WORKDIR/$DMG_NAME"
APPCAST_ARGS=(
  --download-url-prefix "${UPDATE_BASE_URL%/}/"
  --maximum-versions 0
  --maximum-deltas 0
  --versions "$BUILD"
  -o "$APPCAST_WORKDIR/appcast.xml"
  "$APPCAST_WORKDIR"
)
if [[ -n "$SPARKLE_KEY_FILE" ]]; then
  [[ -f "$SPARKLE_KEY_FILE" ]] || fail "Sparkle key file does not exist: $SPARKLE_KEY_FILE"
  "$SPARKLE_TOOL" --ed-key-file "$SPARKLE_KEY_FILE" "${APPCAST_ARGS[@]}"
elif [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_TOOL" --ed-key-file - "${APPCAST_ARGS[@]}"
else
  "$SPARKLE_TOOL" "${APPCAST_ARGS[@]}"
fi
ditto "$APPCAST_WORKDIR/appcast.xml" "$APPCAST_PATH"

if [[ "$PUBLISH" == true ]]; then
  [[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]] || fail "SUPABASE_SERVICE_ROLE_KEY is required with --publish"
  note "Uploading the versioned DMG before publishing appcast.xml"
  upload_file() {
    local source="$1"
    local object_path="$2"
    local content_type="$3"
    curl --fail --show-error --retry 3 --retry-all-errors \
      -X PUT "${SUPABASE_URL%/}/storage/v1/object/$SUPABASE_UPDATES_BUCKET/$object_path" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Content-Type: $content_type" \
      -H "x-upsert: true" \
      --data-binary "@$source"
  }
  upload_file "$DMG_PATH" "$DMG_NAME" "application/x-apple-diskimage"
  upload_file "$APPCAST_PATH" "appcast.xml" "application/xml"
fi

echo "\nRelease artifacts are ready:"
echo "  App:     $APP_PATH"
echo "  DMG:     $DMG_PATH"
echo "  Appcast: $APPCAST_PATH"
if [[ "$PUBLISH" == true ]]; then
  echo "  Feed:    ${UPDATE_BASE_URL%/}/appcast.xml"
fi
