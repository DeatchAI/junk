#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-router-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/AgentCapability.swift" \
  "$app_root/lazzy/Models/AgentProvider.swift" \
  "$app_root/lazzy/Models/AgentModelSettings.swift" \
  "$app_root/lazzy/Models/AgentPermissionMode.swift" \
  "$app_root/lazzy/Models/ActivityJSONValue.swift" \
  "$app_root/lazzy/Models/AgentRunMessages.swift" \
  "$app_root/lazzy/Models/ConversationBranches.swift" \
  "$app_root/lazzy/Models/SlashCommand.swift" \
  "$app_root/lazzy/Models/Routing/"*.swift \
  "$app_root/lazzy/Core/Routing/JevClient.swift" \
  "$app_root/lazzy/Core/Routing/RoutePlanner.swift" \
  "$app_root/lazzy/Core/WebSocket/WebSocketManager+Routing.swift" \
  "$app_root/lazzy/UI/Settings/Routing/RouterTestState.swift" \
  "$app_root/tests/routing/RoutingTestSupport.swift" \
  "$app_root/tests/routing/RoutingTests.swift" \
  -o "$test_dir/router-tests"
"$test_dir/router-tests"
