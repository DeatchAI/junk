#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-setup-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/LaunchAtLoginController.swift" \
  "$app_root/lazzy/Models/AgentProvider.swift" \
  "$app_root/lazzy/UI/Onboarding/AgentReadiness.swift" \
  "$app_root/lazzy/UI/Onboarding/AgentStatusProbe.swift" \
  "$app_root/tests/settings/SetupSettingsTests.swift" \
  -o "$test_dir/setup-tests"
"$test_dir/setup-tests"
