#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
built_app="${1:?Pass the exact rebuilt Detach.app}"
output_dir="${2:?Pass an output directory}"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-notch-render.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
bundle="$test_dir/Preview.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources" "$output_dir"
cp "$app_root/tests/activity-island/PreviewInfo.plist" "$bundle/Info.plist"
cp "$built_app/Contents/Resources/Assets.car" "$bundle/Resources/"
if [[ -f "$built_app/Contents/Resources/Geist-Regular.ttf" ]]; then
  cp "$built_app/Contents/Resources/Geist-Regular.ttf" "$bundle/Resources/"
fi
preview_sources=("$app_root/tests/activity-island/IslandVisualPreview.swift")
if [[ "${3:-}" == "--interactive" ]]; then
  preview_sources=(
    "$app_root/lazzy/UI/DynamicIsland/ActivityIslandWindowController.swift"
    "$app_root/tests/activity-island/IslandInteractionPreview.swift"
  )
elif [[ "${3:-}" == "--self-test" ]]; then
  preview_sources=(
    "$app_root/lazzy/UI/DynamicIsland/ActivityIslandWindowController.swift"
    "$app_root/tests/activity-island/IslandPresentationTests.swift"
  )
fi
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/AppearanceSettings.swift" \
  "$app_root/lazzy/Models/AppFontChoice.swift" \
  "$app_root/lazzy/Core/ThemeDefinitions.swift" \
  "$app_root/lazzy/Core/ThemeManager.swift" \
  "$app_root/lazzy/UI/Components/Appearance/"*.swift \
  "$app_root/lazzy/Core/AppFont.swift" \
  "$app_root/lazzy/Models/SlashCommand.swift" \
  "$app_root/lazzy/Models/AgentModelSettings.swift" \
  "$app_root/lazzy/Models/ActivityJSONValue.swift" \
  "$app_root/lazzy/Models/AgentRunMessages.swift" \
  "$app_root/lazzy/Models/ConversationBranches.swift" \
  "$app_root/lazzy/Models/AgentQuestion.swift" \
  "$app_root/lazzy/Models/AgentProvider.swift" \
  "$app_root/lazzy/Models/ActivityIslandPlacement.swift" \
  "$app_root/lazzy/Core/WebSocket/WebSocketManager+DetachedRuns.swift" \
  "$app_root/lazzy/UI/Components/ScreenEdge/ScreenEdgeNotchShape.swift" \
  "$app_root/lazzy/UI/Components/ScreenEdge/ScreenEdgePanelLayout.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunOutcome.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunProgress.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedAgentRun.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunStore.swift" \
  "$app_root/lazzy/UI/DynamicIsland/DetachedRunControls.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandTaskState.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandContentLayout.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandLayout.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandView.swift" \
  "$app_root/lazzy/UI/DynamicIsland/ActivityIslandTaskList.swift" \
  "$app_root/lazzy/UI/DynamicIsland/Components/"*.swift \
  "$app_root/lazzy/UI/Questions/AgentQuestionCenter.swift" \
  "$app_root/lazzy/UI/Questions/AgentQuestionForm.swift" \
  "$app_root/lazzy/UI/Questions/AgentQuestionKeyboard.swift" \
  "$app_root/tests/activity-island/RunTestSupport.swift" \
  "${preview_sources[@]}" \
  -o "$bundle/MacOS/notch-preview"
if [[ "${3:-}" == "--interactive" || "${3:-}" == "--self-test" ]]; then
  "$bundle/MacOS/notch-preview"
  exit 0
fi
if [[ "${3:-}" == "--compile-only" ]]; then
  echo "Native activity views and preview fixtures compiled successfully"
  exit 0
fi
variant_filter="${3:-all}"
if [[ "$variant_filter" == "all" ]]; then
  variants=(dark light custom glass)
else
  IFS=',' read -r -a variants <<< "$variant_filter"
  for variant in "${variants[@]}"; do
    case "$variant" in
      dark|light|custom|glass) ;;
      *) echo "Unknown appearance '$variant'. Use dark, light, custom, glass, or all." >&2; exit 2 ;;
    esac
  done
fi
for variant in "${variants[@]}"; do
  "$bundle/MacOS/notch-preview" "$output_dir" "$variant"
done
