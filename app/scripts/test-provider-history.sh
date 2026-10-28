#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-provider-history.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/Conversation.swift" \
  "$app_root/lazzy/Models/AgentProvider.swift" \
  "$app_root/lazzy/Models/HistoryProviderGroup.swift" \
  "$app_root/lazzy/Models/ProviderHistoryEvent.swift" \
  "$app_root/lazzy/UI/History/HistoryPaginationState.swift" \
  "$app_root/lazzy/UI/History/ProviderHistoryState.swift" \
  "$app_root/tests/provider-history/ProviderHistoryTests.swift" \
  -o "$test_dir/provider-history-tests"
"$test_dir/provider-history-tests"
