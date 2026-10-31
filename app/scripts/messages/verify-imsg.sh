#!/bin/bash
set -euo pipefail

app_path="${1:?Usage: verify-imsg.sh /path/to/Detach.app}"
helper="$app_path/Contents/Helpers/Imsg"
[[ -x "$helper/imsg" ]] || { echo "error: Bundled Messages helper is missing." >&2; exit 1; }
[[ -f "$helper/PhoneNumberKit_PhoneNumberKit.bundle/Contents/Resources/PhoneNumberMetadata.json" ]]
[[ -f "$helper/SQLite.swift_SQLite.bundle/Contents/Resources/PrivacyInfo.xcprivacy" ]]
[[ -f "$app_path/Contents/Resources/ThirdParty/imsg/imsg.txt" ]]
[[ ! -e "$helper/imsg-bridge-helper.dylib" ]]
/usr/bin/lipo "$helper/imsg" -verify_arch arm64 x86_64
/usr/bin/codesign --verify --strict "$helper/imsg"
for resource_bundle in "$helper/"*.bundle; do
  /usr/bin/codesign --verify --strict "$resource_bundle"
done
purpose="$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "$app_path/Contents/Info.plist")"
[[ "$purpose" == *Messages* ]] || {
  echo "error: The app is missing its Messages permission description." >&2
  exit 1
}
"$helper/imsg" --version
