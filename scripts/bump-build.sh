#!/bin/bash
# =============================================================================
# Build Number Auto-Increment Script
# Increments CURRENT_PROJECT_VERSION in the Xcode project
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_FILE="${PROJECT_ROOT}/lazzy.xcodeproj/project.pbxproj"

if [[ ! -f "$PROJECT_FILE" ]]; then
    echo "❌ project.pbxproj not found at $PROJECT_FILE"
    exit 1
fi

# Get current build number (take the first occurrence)
CURRENT_BUILD=$(grep -m1 "CURRENT_PROJECT_VERSION = " "$PROJECT_FILE" | sed 's/.*= \([0-9]*\);/\1/')

if [[ -z "$CURRENT_BUILD" ]]; then
    echo "❌ Could not find CURRENT_PROJECT_VERSION in project file"
    exit 1
fi

NEW_BUILD=$((CURRENT_BUILD + 1))

echo "📈 Incrementing build: $CURRENT_BUILD → $NEW_BUILD"

# Replace ALL occurrences of CURRENT_PROJECT_VERSION
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PROJECT_FILE"

echo "✅ Build number updated to $NEW_BUILD"
