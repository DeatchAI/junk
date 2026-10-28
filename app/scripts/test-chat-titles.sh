#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-title-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/Conversation.swift" \
  "$app_root/lazzy/Models/ConversationTitleUpdate.swift" \
  "$app_root/tests/conversation-titles/ConversationTitleTests.swift" \
  -o "$test_dir/title-tests"
"$test_dir/title-tests"
