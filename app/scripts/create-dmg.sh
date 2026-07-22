#!/bin/bash

# DMG Creator Script for Lazzy
# Uses Sindre Sorhus's create-dmg for a premium look with an arrow

set -e

# Configuration
APP_NAME="Detach"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="${PROJECT_DIR}/Detach.app"
DMG_NAME="Detach"
OUTPUT_DIR="${PROJECT_DIR}"
FINAL_DMG="${OUTPUT_DIR}/${DMG_NAME}.dmg"

echo "🎨 Creating premium DMG for ${APP_NAME}..."

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: App not found at $APP_PATH"
    echo "   Make sure lazzy.app is in the project root directory"
    exit 1
fi

# Run create-dmg (Sindresorhus)
# This tool automatically creates a beautiful background with an arrow
echo "📀 Building DMG with arrow..."
npx -y create-dmg@latest "${APP_PATH}" "${OUTPUT_DIR}" --overwrite --no-version-in-filename

# The tool creates "Lazzy.dmg", we want "Lazzy.dmg"
TEMP_DMG="${OUTPUT_DIR}/${APP_NAME}.dmg"
if [ -f "$TEMP_DMG" ] && [ "$TEMP_DMG" != "$FINAL_DMG" ]; then
    mv "$TEMP_DMG" "$FINAL_DMG"
fi

echo ""
echo "✅ DMG created successfully with arrow!"
echo "📍 Location: ${FINAL_DMG}"
echo ""
echo "🚀 Ready to distribute to beta testers!"
