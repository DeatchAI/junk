#!/bin/bash

# Standalone Appcast Generator for Sparkle
# Generates appcast.xml from Detach.dmg

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PUBLIC_DIR="${PROJECT_ROOT}"
DMG_PATH="${PROJECT_ROOT}/Detach.dmg"
OUTPUT_XML="${PROJECT_ROOT}/appcast.xml"
TEMP_DIR="/tmp/sparkle-appcast-gen"

# Find generate_appcast tool
SPARKLE_TOOL=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "generate_appcast" -type f 2>/dev/null | head -1)

if [[ ! -x "$SPARKLE_TOOL" ]]; then
    echo "❌ generate_appcast tool not found in DerivedData."
    echo "   Please build the project in Xcode first with Sparkle dependency."
    exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "❌ DMG not found at $DMG_PATH"
    echo "   Run create-dmg.sh first."
    exit 1
fi

echo "🎬 Generating appcast.xml..."

# Prepare temp directory
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Sparkle's generate_appcast looks at all files in a directory.
# We want Detach.dmg to be the one it calculates.
# We rename it to Detach.dmg for the download URL consistency.
cp "$DMG_PATH" "$TEMP_DIR/Detach.dmg"

# Generate
"$SPARKLE_TOOL" "$TEMP_DIR"

if [[ -f "$TEMP_DIR/appcast.xml" ]]; then
    cp "$TEMP_DIR/appcast.xml" "$OUTPUT_XML"
    echo "✅ Successfully generated appcast.xml at $OUTPUT_XML"
    
    # Show the generated item details
    grep -A 5 "<item>" "$OUTPUT_XML"
else
    echo "❌ Failed to generate appcast.xml"
    exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"
