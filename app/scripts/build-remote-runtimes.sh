#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_ROOT="$(cd "$SCRIPT_DIR/../server-v2" && pwd)"
OUTPUT_DIR="${1:-$SERVER_ROOT/remote-runtimes}"

mkdir -p "$OUTPUT_DIR"
cd "$SERVER_ROOT"

build_target() {
  local target="$1"
  local platform="$2"
  local output="$OUTPUT_DIR/detach-runtime-$platform"
  echo "Building remote runtime for $platform"
  bun build --compile --target="bun-$target" --outfile "$output" src/index.ts
  chmod 755 "$output"
}

build_target darwin-arm64 darwin-arm64
build_target darwin-x64 darwin-x64
build_target linux-arm64 linux-arm64
build_target linux-x64 linux-x64
