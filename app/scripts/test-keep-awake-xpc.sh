#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
identity="${DETACH_TEST_SIGNING_IDENTITY:?Set DETACH_TEST_SIGNING_IDENTITY to an Apple Development identity}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-keep-awake-xpc.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/PowerHelper/PowerGuardEngine.swift" \
  "$app_root/PowerHelper/PowerGuardJournal.swift" \
  "$app_root/PowerHelper/SystemPowerBackend.swift" \
  "$app_root/PowerHelper/PowerSafety.swift" \
  "$app_root/PowerHelper/PowerGuardService.swift" \
  "$app_root/lazzy/Core/KeepAwake/KeepAwakeProtocol.swift" \
  "$app_root/tests/keep-awake/PowerGuardXPCTests.swift" \
  -o "$test_dir/keep-awake-xpc-tests"
codesign --force --sign "$identity" --identifier app.getlazzy "$test_dir/keep-awake-xpc-tests"
cp "$test_dir/keep-awake-xpc-tests" "$test_dir/untrusted-client"
codesign --force --sign "$identity" --identifier app.getlazzy.untrusted "$test_dir/untrusted-client"
"$test_dir/keep-awake-xpc-tests"
"$test_dir/untrusted-client" --expect-rejected
