#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
test -n "$TMPDIR" || { echo "TMPDIR must be set" >&2; exit 1; }
build_dir="$(mktemp -d "$TMPDIR/detach-poll-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$build_dir/modules" \
  "$script_dir/../../lazzy/Core/Messages/Automation/PollAccessibility.swift" \
  "$script_dir/../../lazzy/Core/Messages/Automation/PollRequest.swift" \
  "$script_dir/../../tests/messages/automation/PollAutomationTests.swift" \
  -o "$build_dir/tests"
"$build_dir/tests"
