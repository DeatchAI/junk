#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-activity-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/ActivityIslandPlacement.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandLayout.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandContentLayout.swift" \
  "$app_root/lazzy/UI/Components/ScreenEdge/ScreenEdgeNotchShape.swift" \
  "$app_root/lazzy/UI/Components/ScreenEdge/ScreenEdgePanelLayout.swift" \
  "$app_root/lazzy/UI/History/HistoryPanelLayout.swift" \
  "$app_root/tests/activity-island/LayoutTests.swift" \
  -o "$test_dir/layout-tests"
"$test_dir/layout-tests"
