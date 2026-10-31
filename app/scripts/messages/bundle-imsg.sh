#!/bin/bash
set -euo pipefail

# Only build machines download this pinned release. The shipped app is self contained.
imsg_version="0.20.0"
imsg_sha256="9370793485cb9f9ae060286be978c7e971dbd799613017fddcd913d1366dcb75"
imsg_url="https://github.com/openclaw/imsg/releases/download/v${imsg_version}/imsg-macos.zip"
app_root="$(cd "$(dirname "$0")/../.." && pwd)"
cache_dir="${PROJECT_TEMP_DIR:?}/messages-helper/${imsg_version}"
destination="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}/Helpers/Imsg"
notices="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/ThirdParty/imsg"
mkdir -p "$cache_dir"

archive="${DETACH_IMSG_ARCHIVE:-$cache_dir/imsg-macos.zip}"
checksum() { /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'; }
if [[ ! -f "$archive" || "$(checksum "$archive")" != "$imsg_sha256" ]]; then
  [[ -z "${DETACH_IMSG_ARCHIVE:-}" ]] || {
    echo "error: The supplied imsg archive does not match the pinned checksum." >&2
    exit 1
  }
  download="$(mktemp "$cache_dir/download.XXXXXX")"
  trap 'rm -f "${download:-}"' EXIT
  /usr/bin/curl --fail --silent --show-error --location --connect-timeout 15 \
    --max-time 120 --proto '=https' --tlsv1.2 "$imsg_url" -o "$download"
  [[ "$(checksum "$download")" == "$imsg_sha256" ]] || {
    echo "error: imsg download failed checksum verification." >&2
    exit 1
  }
  /bin/mv "$download" "$archive"
fi

staging="$(mktemp -d "$cache_dir/staging.XXXXXX")"
trap 'rm -rf "$staging"; rm -f "${download:-}"' EXIT
# The optional injected bridge is deliberately excluded from the app.
/usr/bin/unzip -oq "$archive" imsg 'SQLite.swift_SQLite.bundle/*' \
  'PhoneNumberKit_PhoneNumberKit.bundle/*' -d "$staging"
/usr/bin/codesign --verify --strict \
  -R='anchor apple generic and certificate leaf[subject.OU] = "Y5PE65HELJ"' "$staging/imsg"
/usr/bin/lipo "$staging/imsg" -verify_arch arm64 x86_64

[[ -f "$staging/PhoneNumberKit_PhoneNumberKit.bundle/Contents/Resources/PhoneNumberMetadata.json" ]]
[[ -f "$staging/SQLite.swift_SQLite.bundle/Contents/Resources/PrivacyInfo.xcprivacy" ]]
/bin/mkdir -p "$(dirname "$destination")" "$notices"
/bin/rm -rf "$destination"
/usr/bin/ditto "$staging" "$destination"
/bin/chmod 755 "$destination/imsg"
/usr/bin/ditto "$app_root/ThirdParty/imsg" "$notices"
printf '%s\n' "$imsg_version" > "$notices/version.txt"

if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  timestamp=(--timestamp)
  [[ "${CONFIGURATION:-Debug}" != "Debug" ]] || timestamp=(--timestamp=none)
  for resource_bundle in "$destination/"*.bundle; do
    /usr/bin/codesign --force "${timestamp[@]}" \
      --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$resource_bundle"
  done
  /usr/bin/codesign --force --options runtime "${timestamp[@]}" \
    --identifier "${PRODUCT_BUNDLE_IDENTIFIER:-app.getlazzy}.messages-helper" \
    --entitlements "$app_root/scripts/messages/helper.entitlements" \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$destination/imsg"
fi
echo "Bundled Messages helper $imsg_version (Intel and Apple Silicon)"
