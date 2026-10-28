#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-provider-catalog.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/AgentProvider.swift" \
  "$app_root/lazzy/Models/AgentModelSettings.swift" \
  "$app_root/lazzy/Models/AgentPermissionMode.swift" \
  "$app_root/lazzy/Models/AISettings.swift" \
  "$app_root/lazzy/UI/Onboarding/LocalAgentDetector.swift" \
  "$app_root/tests/providers/ProviderCatalogTests.swift" \
  -o "$test_dir/provider-tests"
"$test_dir/provider-tests" "$app_root/lazzy/Assets.xcassets"
