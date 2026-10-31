#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-notch-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/SlashCommand.swift" \
  "$app_root/lazzy/Models/AgentModelSettings.swift" \
  "$app_root/lazzy/Models/ActivityJSONValue.swift" \
  "$app_root/lazzy/Models/AgentRunMessages.swift" \
  "$app_root/lazzy/Models/ConversationBranches.swift" \
  "$app_root/lazzy/Core/WebSocket/WebSocketManager+DetachedRuns.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunOutcome.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunProgress.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedAgentRun.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunStore.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunControls.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandTaskState.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandContentLayout.swift" \
  "$app_root/tests/activity-island/RunTestSupport.swift" \
  "$app_root/tests/activity-island/UnreadResultTests.swift" \
  "$app_root/tests/activity-island/TaskInteractionTests.swift" \
  "$app_root/tests/activity-island/RunStateTests.swift" \
  -o "$test_dir/run-tests"
"$test_dir/run-tests"
