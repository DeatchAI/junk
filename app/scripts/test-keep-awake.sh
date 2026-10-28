#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-keep-awake.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/PowerHelper/PowerGuardEngine.swift" \
  "$app_root/tests/keep-awake/PowerGuardTests.swift" \
  -o "$test_dir/keep-awake-tests"
"$test_dir/keep-awake-tests"
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/SlashCommand.swift" \
  "$app_root/lazzy/Models/AgentModelSettings.swift" \
  "$app_root/lazzy/Models/ActivityJSONValue.swift" \
  "$app_root/lazzy/Models/AgentRunMessages.swift" \
  "$app_root/lazzy/Models/ConversationBranches.swift" \
  "$app_root/lazzy/Core/WebSocket/WebSocketManager+DetachedRuns.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunOutcome.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedAgentRun.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunStore.swift" \
  "$app_root/lazzy/Core/KeepAwake/KeepAwakeWorkPolicy.swift" \
  "$app_root/tests/activity-island/RunTestSupport.swift" \
  "$app_root/tests/keep-awake/KeepAwakeWorkPolicyTests.swift" \
  -o "$test_dir/keep-awake-work-tests"
"$test_dir/keep-awake-work-tests"
