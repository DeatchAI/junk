#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-desktop-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root"/lazzy/Core/DesktopAutomation/*.swift \
  "$app_root/lazzy/Core/NativePermissionRequests.swift" \
  "$app_root/tests/desktop/DesktopContractTests.swift" -o "$test_dir/desktop-tests"
"$test_dir/desktop-tests"
