#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-appearance.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
bundle="$test_dir/AppearanceChecks.app/Contents"
mkdir -p "$bundle/MacOS"
cat > "$bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.detach.appearance-checks</string>
<key>CFBundleExecutable</key><string>appearance-checks</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
sources=(
  "$app_root/lazzy/Models/AppearanceSettings.swift"
  "$app_root/lazzy/Core/ThemeDefinitions.swift"
  "$app_root/lazzy/Core/ThemeManager.swift"
  "$app_root/lazzy/UI/Components/Appearance/"*.swift
  "$app_root/lazzy/UI/Components/FirstClickHostingView.swift"
  "$app_root/tests/appearance/AppearanceSurfaceTests.swift"
)
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
# Compile the fallback branches at the app's existing minimum deployment target.
xcrun swiftc -sdk "$sdk_path" -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$test_dir/modules" "${sources[@]}" \
  -o "$bundle/MacOS/appearance-checks"
"$bundle/MacOS/appearance-checks"
"$bundle/MacOS/appearance-checks" --check-saved-translucency
