#!/usr/bin/env bash

# Run the same checks expected from a contributor pull request.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

require_command() {
  command -v "$1" >/dev/null || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_command bun
require_command npm
require_command xcodebuild

if [[ ! -f "$ROOT_DIR/web/package.json" ]]; then
  echo "The web submodule is not checked out. Run: git submodule update --init --recursive" >&2
  exit 1
fi

echo "==> Checking the local runtime"
(
  cd "$ROOT_DIR/app/server-v2"
  bun install --frozen-lockfile
  bun run check
)

echo "==> Building the macOS app without signing"
xcodebuild \
  -project "$ROOT_DIR/app/detach.xcodeproj" \
  -scheme lazzy \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "${TMPDIR:-/tmp}/detach-derived-data" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Checking the website"
(
  cd "$ROOT_DIR/web"
  npm ci
  npm run lint
  npm run build
)

echo "All checks passed."
