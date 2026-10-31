#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-git-ui.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
export DETACH_GIT_REVIEW_OUTPUT="${1:-/tmp/detach-git-review-native}"
mkdir -p "$DETACH_GIT_REVIEW_OUTPUT"
xcrun swiftc -parse-as-library -D GIT_REVIEW_STANDALONE \
  -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/App/Constants.swift" \
  "$app_root/lazzy/Core/AppFont.swift" \
  "$app_root/lazzy/Core/ThemeManager.swift" \
  "$app_root/lazzy/Core/ThemeDefinitions.swift" \
  "$app_root/lazzy/Models/AppearanceSettings.swift" \
  "$app_root/lazzy/Models/AppFontChoice.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Components/ComposerButtonStyle.swift" \
  "$app_root/lazzy/UI/Components/FirstClickHostingView.swift" \
  "$app_root/lazzy/UI/Components/DropdownPanelAnchor.swift" \
  "$app_root/lazzy/UI/Components/DropdownPanelLayout.swift" \
  "$app_root/lazzy/UI/Components/DropdownPanelSession.swift" \
  "$app_root/lazzy/UI/Components/Controls/AppControlStyle.swift" \
  "$app_root/lazzy/UI/Components/Controls/AppActionMenu.swift" \
  "$app_root/lazzy/UI/Components/Controls/AppSelect.swift" \
  "$app_root/lazzy/Models/ConversationBranches.swift" \
  "$app_root/lazzy/Core/Git/"*.swift \
  "$app_root/lazzy/UI/Changes/"*.swift \
  "$app_root/tests/git-review/GitReviewNativeRegression.swift" \
  -o "$test_dir/git-review-ui"
"$test_dir/git-review-ui"
python3 - "$DETACH_GIT_REVIEW_OUTPUT/result.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
print(json.dumps(result, indent=2))
sys.exit(0 if result["passed"] else 1)
PY
