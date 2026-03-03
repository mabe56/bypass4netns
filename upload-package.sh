#!/bin/bash
# upload-package.sh - Upload Debian package to GitLab Generic Package Registry
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Configuration - Edit these values for your GitLab instance
GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
GITLAB_PROJECT_ID="${GITLAB_PROJECT_ID:-}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
PACKAGE_NAME="bypass4netns"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] <package-file.deb>

Upload a Debian package to GitLab Generic Package Registry.

OPTIONS:
    -h, --help              Show this help message
    -u, --url URL           GitLab URL (default: https://gitlab.com)
    -p, --project-id ID     GitLab project ID (required)
    -t, --token TOKEN       GitLab Personal Access Token (required)
    
ENVIRONMENT VARIABLES:
    GITLAB_URL              GitLab instance URL
    GITLAB_PROJECT_ID       Project ID
    GITLAB_TOKEN            Personal access token with api scope

EXAMPLES:
    # Using command line arguments
    $0 -p 123 -t glpat-xxx bypass4netns_1.0.0_amd64.deb
    
    # Using environment variables
    export GITLAB_URL=https://gitlab.com
    export GITLAB_PROJECT_ID=123
    export GITLAB_TOKEN=glpat-xxx
    $0 bypass4netns_1.0.0_amd64.deb

GETTING A TOKEN:
    1. Go to ${GITLAB_URL}/-/user_settings/personal_access_tokens
    2. Create a token with 'api' scope
    3. Save the token securely
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -u|--url)
            GITLAB_URL="$2"
            shift 2
            ;;
        -p|--project-id)
            GITLAB_PROJECT_ID="$2"
            shift 2
            ;;
        -t|--token)
            GITLAB_TOKEN="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            PACKAGE_FILE="$1"
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "${PACKAGE_FILE:-}" ]; then
    log_error "No package file specified"
    usage
fi

if [ ! -f "$PACKAGE_FILE" ]; then
    log_error "Package file not found: $PACKAGE_FILE"
    exit 1
fi

if [ ! "${PACKAGE_FILE##*.}" = "deb" ]; then
    log_error "File must be a .deb package"
    exit 1
fi

if [ -z "$GITLAB_PROJECT_ID" ]; then
    log_error "GitLab project ID not specified"
    echo "Set GITLAB_PROJECT_ID environment variable or use -p flag"
    exit 1
fi

if [ -z "$GITLAB_TOKEN" ]; then
    log_error "GitLab token not specified"
    echo "Set GITLAB_TOKEN environment variable or use -t flag"
    exit 1
fi

# Extract version from filename (bypass4netns_VERSION_ARCH.deb)
BASENAME=$(basename "$PACKAGE_FILE" .deb)
VERSION=$(echo "$BASENAME" | cut -d'_' -f2)

if [ -z "$VERSION" ]; then
    log_error "Could not extract version from filename"
    log_error "Expected format: bypass4netns_VERSION_ARCH.deb"
    exit 1
fi

# Construct GitLab API URL
API_URL="${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages/generic/${PACKAGE_NAME}/${VERSION}/$(basename "$PACKAGE_FILE")"

log_info "Uploading package to GitLab..."
echo "  URL:     $GITLAB_URL"
echo "  Project: $GITLAB_PROJECT_ID"
echo "  Package: $PACKAGE_NAME"
echo "  Version: $VERSION"
echo "  File:    $(basename "$PACKAGE_FILE")"
echo "  Size:    $(du -h "$PACKAGE_FILE" | cut -f1)"
echo ""

# Upload the package
HTTP_CODE=$(curl -w "%{http_code}" -o /tmp/gitlab-upload-response.json \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --upload-file "$PACKAGE_FILE" \
    --progress-bar \
    "$API_URL")

echo "" # New line after progress bar

# Check response
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    log_info "Package uploaded successfully! (HTTP $HTTP_CODE)"
    
    # Upload checksums if they exist
    if [ -f "${PACKAGE_FILE}.sha256" ]; then
        log_info "Uploading SHA256 checksum..."
        curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --upload-file "${PACKAGE_FILE}.sha256" \
            "${API_URL}.sha256" > /dev/null
    fi
    
    if [ -f "${PACKAGE_FILE}.md5" ]; then
        log_info "Uploading MD5 checksum..."
        curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            --upload-file "${PACKAGE_FILE}.md5" \
            "${API_URL}.md5" > /dev/null
    fi
    
    echo ""
    log_info "Download URL:"
    echo "  ${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages/generic/${PACKAGE_NAME}/${VERSION}/$(basename "$PACKAGE_FILE")"
    echo ""
    log_info "Install with:"
    echo "  curl --header \"PRIVATE-TOKEN: \$GITLAB_TOKEN\" \\"
    echo "       \"${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages/generic/${PACKAGE_NAME}/${VERSION}/$(basename "$PACKAGE_FILE")\" \\"
    echo "       -o bypass4netns.deb && sudo apt install ./bypass4netns.deb"
    
else
    log_error "Upload failed with HTTP code $HTTP_CODE"
    if [ -f /tmp/gitlab-upload-response.json ]; then
        cat /tmp/gitlab-upload-response.json
        echo ""
    fi
    rm -f /tmp/gitlab-upload-response.json
    exit 1
fi

rm -f /tmp/gitlab-upload-response.json
