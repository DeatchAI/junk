#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-transcript-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/UI/Components/Appearance/"*.swift \
  "$app_root/lazzy/Core/AppFont.swift" \
  "$app_root/lazzy/Core/ThemeManager.swift" \
  "$app_root/lazzy/Core/ThemeDefinitions.swift" \
  "$app_root/lazzy/Models/AppearanceSettings.swift" \
  "$app_root/lazzy/Models/Message.swift" \
  "$app_root/lazzy/Models/ActivityJSONValue.swift" \
  "$app_root/lazzy/Models/ChatTranscript.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Components/MarkdownParser.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Components/SelectableTextView.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Components/MarkdownMessageView.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Components/Transcript/ChatTranscriptView.swift" \
  "$app_root/tests/chat-transcript/ChatTranscriptTests.swift" \
  -o "$test_dir/chat-transcript-tests"
if [[ $# -gt 0 ]]; then mkdir -p "$1"; fi
"$test_dir/chat-transcript-tests" "$@"
