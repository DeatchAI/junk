#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-composer-projects.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Models/Workspace/ComposerProjectLibrary.swift" \
  "$app_root/lazzy/Models/Workspace/WorkingDirectoryStore.swift" \
  "$app_root/tests/composer/WorkspaceProjectTests.swift" \
  -o "$test_dir/project-tests"
"$test_dir/project-tests"
