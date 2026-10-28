#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-conversation-attachments.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/Conversation.swift" \
  "$app_root/lazzy/Models/Message.swift" \
  "$app_root/lazzy/Models/ChatAttachment.swift" \
  "$app_root/lazzy/Core/WebSocket/HistoryConversationLoader.swift" \
  "$app_root/lazzy/Models/Workspace/ConversationTranscriptAttachment.swift" \
  "$app_root/lazzy/Models/Workspace/ComposerConversationStore.swift" \
  "$app_root/tests/composer/ConversationAttachmentTests.swift" \
  -o "$test_dir/conversation-attachment-tests"
"$test_dir/conversation-attachment-tests"
