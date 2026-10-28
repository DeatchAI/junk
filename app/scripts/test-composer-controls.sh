#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-composer-controls.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/UI/Components/FirstClickHostingView.swift" \
  "$app_root/lazzy/UI/Components/DropdownPanelLayout.swift" \
  "$app_root/lazzy/UI/Components/DropdownPanelSession.swift" \
  "$app_root/lazzy/UI/Components/DropdownPanelAnchor.swift" \
  "$app_root/tests/composer/DropdownInteractionTests.swift" \
  -o "$test_dir/composer-tests"
"$test_dir/composer-tests"
