#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-history-transport.XXXXXX")"
fixture_pid=""
cleanup() {
  if [[ -n "$fixture_pid" ]]; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  rm -rf "$test_dir"
}
trap cleanup EXIT
xcrun swiftc -parse-as-library -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/Conversation.swift" \
  "$app_root/lazzy/Models/Message.swift" \
  "$app_root/lazzy/Core/WebSocket/HistoryConversationLoader.swift" \
  "$app_root/tests/provider-history/HistoryTransportTests.swift" \
  -o "$test_dir/history-transport-tests"
bun run "$app_root/tests/provider-history/HistoryTransportFixture.ts" "$test_dir/connection.json" &
fixture_pid=$!
"$test_dir/history-transport-tests" "$test_dir/connection.json"
