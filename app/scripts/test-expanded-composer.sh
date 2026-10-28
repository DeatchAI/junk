#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-expanded-composer.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Core/WindowUtils.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Window/FloatingComposerPanel.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Window/FloatingChatWindowLayout.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Window/FloatingChatExpandedLayout.swift" \
  "$app_root/lazzy/UI/Components/FirstClickHostingView.swift" \
  "$app_root/tests/composer/ExpandedViewportTests.swift" \
  "$app_root/tests/composer/ExpandedLayoutTests.swift" \
  -o "$test_dir/expanded-composer-tests"
"$test_dir/expanded-composer-tests"
