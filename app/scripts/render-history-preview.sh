#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
built_app="${1:?Pass the exact rebuilt Detach.app}"
output_dir="${2:?Pass an output directory}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-history-render.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
bundle="$test_dir/Preview.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources" "$output_dir"
cp "$app_root/tests/activity-island/PreviewInfo.plist" "$bundle/Info.plist"
cp "$built_app/Contents/Resources/Assets.car" "$bundle/Resources/"
if [[ -f "$built_app/Contents/Resources/Geist-Regular.ttf" ]]; then
  cp "$built_app/Contents/Resources/Geist-Regular.ttf" "$bundle/Resources/"
fi
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Core/AppFont.swift" \
  "$app_root/lazzy/Core/ThemeManager.swift" \
  "$app_root/lazzy/Core/ThemeDefinitions.swift" \
  "$app_root/lazzy/Models/AppearanceSettings.swift" \
  "$app_root/lazzy/UI/Components/Appearance/"*.swift \
  "$app_root/lazzy/Models/Conversation.swift" \
  "$app_root/lazzy/Models/ProviderHistoryEvent.swift" \
  "$app_root/lazzy/Models/AgentProvider.swift" \
  "$app_root/lazzy/Models/HistoryProviderGroup.swift" \
  "$app_root/lazzy/Models/ActivityIslandPlacement.swift" \
  "$app_root/lazzy/UI/Components/ScreenEdge/ScreenEdgeNotchShape.swift" \
  "$app_root/lazzy/UI/History/HistoryPanelView.swift" \
  "$app_root/lazzy/UI/History/HistoryRowView.swift" \
  "$app_root/lazzy/UI/History/HistoryChatList.swift" \
  "$app_root/lazzy/UI/FloatingWindow/Components/Icons/ComposerIcons.swift" \
  "$app_root/lazzy/UI/History/HistoryPaginationState.swift" \
  "$app_root/lazzy/UI/History/HistoryClickAwayMonitor.swift" \
  "$app_root/lazzy/UI/History/HistoryPanelSurface.swift" \
  "$app_root/lazzy/UI/History/ProviderHistoryState.swift" \
  "$app_root/tests/provider-history/HistoryPreviewSupport.swift" \
  "$app_root/tests/provider-history/HistoryVisualPreview.swift" \
  -o "$bundle/MacOS/history-preview"
"$bundle/MacOS/history-preview" "$output_dir" directory-light
"$bundle/MacOS/history-preview" "$output_dir" directory-dark
"$bundle/MacOS/history-preview" "$output_dir" directory-glass
