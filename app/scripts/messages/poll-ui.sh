#!/bin/bash
set -euo pipefail

# Cache only a locally compiled prototype, outside the repository.
script_dir="$(cd "$(dirname "$0")" && pwd)"
source_dir="$script_dir/../../lazzy/Core/Messages/Automation"
test -n "$TMPDIR" || { echo "TMPDIR must be set" >&2; exit 1; }
cache_root="$TMPDIR/detach-poll-ui-$UID"
mkdir -p "$cache_root"
chmod 700 "$cache_root"
source_hash="$(shasum -a 256 "$source_dir"/*.swift "$script_dir/poll-ui/PollCommand.swift" | shasum -a 256 | cut -d ' ' -f 1)"
binary="$cache_root/poll-ui-$source_hash"
if [[ ! -x "$binary" ]]; then
  build_dir="$(mktemp -d "$cache_root/build.XXXXXX")"
  trap 'rm -rf "$build_dir"' EXIT
  xcrun swiftc -swift-version 5 -module-cache-path "$cache_root/modules" \
    "$source_dir"/*.swift "$script_dir/poll-ui/PollCommand.swift" -o "$build_dir/poll-ui"
  mv "$build_dir/poll-ui" "$binary"
fi
exec "$binary" "$@"
