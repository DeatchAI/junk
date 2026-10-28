#!/bin/bash
set -euo pipefail

app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-question-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT

xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/AppearanceSettings.swift" \
  "$app_root/lazzy/Core/ThemeDefinitions.swift" \
  "$app_root/lazzy/Core/ThemeManager.swift" \
  "$app_root/lazzy/UI/Components/Appearance/"*.swift \
  "$app_root/lazzy/Models/AgentQuestion.swift" \
  "$app_root/lazzy/UI/Questions/AgentQuestionCenter.swift" \
  "$app_root/lazzy/UI/Questions/AgentQuestionForm.swift" \
  "$app_root/tests/questions/QuestionStateTests.swift" \
  -o "$test_dir/question-tests"
"$test_dir/question-tests"
