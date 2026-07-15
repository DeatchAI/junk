#!/bin/bash
# =============================================================================
# Lazzy Release Script
# Automates: Notarization → Staple → DMG → Appcast → Upload to Supabase
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APPLE_ID="yakshitchhipa@gmail.com"
TEAM_ID="RZJT39VU7M"
SIGNING_IDENTITY="Developer ID Application: Yakshit Chhipa (RZJT39VU7M)"
KEYCHAIN_PROFILE="notary-lazzy"
SUPABASE_BUCKET_URL="https://qymrzmmsroxkteaxbgoo.supabase.co/storage/v1/object/public/updates"
APP_NAME="Detach"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PUBLIC_DIR="${PROJECT_ROOT}/web/public"
WORKING_APP="${PROJECT_ROOT}/Detach.app"
DMG_NAME="Detach"
FINAL_DMG="${PUBLIC_DIR}/${DMG_NAME}.dmg"

# Parse arguments
SKIP_NOTARIZE=false
SKIP_UPLOAD=false
VERSION=""

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VER     Version for release notes"
    echo "  --skip-notarize   Skip notarization (for testing)"
    echo "  --skip-upload     Skip Supabase upload"
    echo "  --setup           Set up notarytool credentials"
    echo "  -h, --help        Show this help message"
}

log_step() { echo -e "\n${BLUE}▶ $1${NC}"; }
log_success() { echo -e "${GREEN}✓ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_error() { echo -e "${RED}✗ $1${NC}" >&2; }

# Setup notarytool credentials
setup_credentials() {
    log_step "Setting up notarytool credentials..."
    xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --skip-upload)
            SKIP_UPLOAD=true
            shift
            ;;
        --setup)
            setup_credentials
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# =============================================================================
# STEP 0: Validate prerequisites
# =============================================================================
log_step "Validating prerequisites..."

if [[ ! -d "$WORKING_APP" ]]; then
    log_error "App not found at $WORKING_APP. Please build it first."
    exit 1
fi

APP_VERSION=$(defaults read "$WORKING_APP/Contents/Info" CFBundleShortVersionString)
BUILD_NUMBER=$(defaults read "$WORKING_APP/Contents/Info" CFBundleVersion)
log_success "Found app version: $APP_VERSION (Build $BUILD_NUMBER)"

# =============================================================================
# STEP 1: Notarize
# =============================================================================
if [[ "$SKIP_NOTARIZE" == true ]]; then
    log_warning "Skipping notarization (--skip-notarize flag)"
else
    log_step "Submitting for notarization..."
    
    ZIP_PATH="${PROJECT_ROOT}/${APP_NAME}-notarize.zip"
    ditto -c -k --keepParent "$WORKING_APP" "$ZIP_PATH"
    
    # Check if keychain profile exists
    if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
        xcrun notarytool submit "$ZIP_PATH" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --wait
    else
        xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    fi
    
    if [[ $? -eq 0 ]]; then
        log_success "Notarization successful"
        log_step "Stapling notarization ticket..."
        xcrun stapler staple "$WORKING_APP"
        log_success "Ticket stapled"
    else
        log_error "Notarization failed"
        exit 1
    fi
    
    rm -f "$ZIP_PATH"
fi

# =============================================================================
# STEP 2: Create DMG
# =============================================================================
log_step "Creating premium DMG..."
"${SCRIPT_DIR}/create-dmg.sh"
log_success "DMG created at $FINAL_DMG"

# =============================================================================
# STEP 3: Generate appcast.xml
# =============================================================================
log_step "Generating appcast.xml..."
"${SCRIPT_DIR}/generate-appcast.sh"

# =============================================================================
# STEP 4: Upload to Supabase (if not skipped)
# =============================================================================
if [[ "$SKIP_UPLOAD" == true ]]; then
    log_warning "Skipping upload (--skip-upload flag)"
else
    log_step "Uploading to Supabase..."
    
    if [[ -z "${SUPABASE_SERVICE_KEY:-}" ]]; then
        log_warning "SUPABASE_SERVICE_KEY not set. Skipping upload."
    else
        SUPABASE_PROJECT_URL="https://qymrzmmsroxkteaxbgoo.supabase.co"
        
        # Upload DMG (use PUT with x-upsert to create or replace)
        log_step "Uploading DMG (~37MB, this may take a moment)..."
        curl -X PUT "$SUPABASE_PROJECT_URL/storage/v1/object/updates/${DMG_NAME}.dmg" \
            -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
            -H "Content-Type: application/octet-stream" \
            -H "x-upsert: true" \
            --data-binary @"$FINAL_DMG" \
            --fail --show-error || { log_error "Failed to upload DMG"; exit 1; }
        log_success "DMG uploaded"
        
        # Upload appcast.xml (use PUT with x-upsert to create or replace)
        curl -X PUT "$SUPABASE_PROJECT_URL/storage/v1/object/updates/appcast.xml" \
            -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
            -H "Content-Type: application/xml" \
            -H "x-upsert: true" \
            --data-binary @"$PROJECT_ROOT/appcast.xml" \
            --fail --show-error || { log_error "Failed to upload appcast.xml"; exit 1; }
        log_success "appcast.xml uploaded"
            
        log_success "Upload complete"
    fi
fi

echo -e "\n${GREEN}🎉 RELEASE COMPLETE!${NC}"
echo "Version:    $APP_VERSION (Build $BUILD_NUMBER)"
echo "Update URL: $SUPABASE_BUCKET_URL/appcast.xml"

