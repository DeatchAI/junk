#!/bin/bash
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/detach-git-review.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$test_dir/modules" \
  "$app_root/lazzy/Core/Git/GitReviewTypes.swift" \
  "$app_root/lazzy/Core/Git/GitDiffLines.swift" \
  "$app_root/lazzy/Core/Git/GitFileTree.swift" \
  "$app_root/tests/git-review/GitReviewTests.swift" \
  -o "$test_dir/git-review-tests"
"$test_dir/git-review-tests"
