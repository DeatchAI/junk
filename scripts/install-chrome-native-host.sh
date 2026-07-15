#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKSPACE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
HOST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
HOST_PATH="$WORKSPACE_DIR/chrome-extension/native-host/com.lazzy.browser"
MANIFEST_PATH="$HOST_DIR/com.lazzy.browser.json"
EXTENSION_ID="gdobcabflbojkedmocahijccipghgoij"

chmod +x "$HOST_PATH"
mkdir -p "$HOST_DIR"

python3 - "$MANIFEST_PATH" "$HOST_PATH" "$EXTENSION_ID" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
host_path = pathlib.Path(sys.argv[2])
extension_id = sys.argv[3]

manifest = {
    "name": "com.lazzy.browser",
    "description": "Detach Browser Agent native bridge",
    "path": str(host_path),
    "type": "stdio",
    "allowed_origins": [
        f"chrome-extension://{extension_id}/"
    ],
}

manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

echo "$MANIFEST_PATH"
