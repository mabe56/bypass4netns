#!/bin/bash
# install-from-gitlab.sh - Download and install bypass4netns from GitLab
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
VERSION="${VERSION:-latest}"

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Download and install bypass4netns Debian package from GitLab.

OPTIONS:
    -h, --help              Show this help message
    -u, --url URL           GitLab URL (default: https://gitlab.com)
    -p, --project-id ID     GitLab project ID (required)
    -t, --token TOKEN       GitLab Personal Access Token (required)
    -v, --version VERSION   Package version (default: latest)
    --download-only         Download only, don't install
    --verify                Verify checksums after download
    
ENVIRONMENT VARIABLES:
    GITLAB_URL              GitLab instance URL
    GITLAB_PROJECT_ID       Project ID
    GITLAB_TOKEN            Personal access token with api scope
    VERSION                 Package version to install

EXAMPLES:
    # Install latest version
    sudo -E $0 -p 123 -t glpat-xxx
    
    # Install specific version
    sudo -E $0 -p 123 -t glpat-xxx -v 1.0.0
    
    # Download only (for inspection)
    $0 -p 123 -t glpat-xxx --download-only
    
    # Using environment variables
    export GITLAB_URL=https://gitlab.com
    export GITLAB_PROJECT_ID=123
    export GITLAB_TOKEN=glpat-xxx
    sudo -E $0

NOTE:
    This script requires sudo for installation. Use 'sudo -E' to preserve
    environment variables.
EOF
    exit 1
}

# Parse arguments
DOWNLOAD_ONLY=false
VERIFY_CHECKSUM=false

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
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        --download-only)
            DOWNLOAD_ONLY=true
            shift
            ;;
        --verify)
            VERIFY_CHECKSUM=true
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            log_error "Unexpected argument: $1"
            usage
            ;;
    esac
done

# Validate inputs
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

# Check if we need sudo for installation
if [ "$DOWNLOAD_ONLY" = false ] && [ "$EUID" -ne 0 ]; then
    log_error "Installation requires root privileges"
    echo "Please run with sudo: sudo -E $0 $*"
    exit 1
fi

# Get latest version if not specified
if [ "$VERSION" = "latest" ]; then
    log_info "Fetching latest version from GitLab..."
    
    API_URL="${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages?package_name=${PACKAGE_NAME}&per_page=1&sort=desc"
    
    LATEST_VERSION=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$API_URL" | \
        grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
    
    if [ -z "$LATEST_VERSION" ]; then
        log_error "Could not fetch latest version from GitLab"
        log_error "Please specify version with -v flag"
        exit 1
    fi
    
    VERSION="$LATEST_VERSION"
    log_info "Latest version: $VERSION"
fi

# Determine architecture
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
PACKAGE_FILE="${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
DOWNLOAD_URL="${GITLAB_URL}/api/v4/projects/${GITLAB_PROJECT_ID}/packages/generic/${PACKAGE_NAME}/${VERSION}/${PACKAGE_FILE}"

log_info "Downloading package..."
echo "  Version:      $VERSION"
echo "  Architecture: $ARCH"
echo "  File:         $PACKAGE_FILE"
echo ""

# Create temporary directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Download package
HTTP_CODE=$(curl -w "%{http_code}" -o "${TMP_DIR}/${PACKAGE_FILE}" \
    --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
    --progress-bar \
    "$DOWNLOAD_URL")

echo "" # New line after progress bar

if [ "$HTTP_CODE" -ne 200 ]; then
    log_error "Download failed with HTTP code $HTTP_CODE"
    if [ "$HTTP_CODE" -eq 404 ]; then
        log_error "Package not found. Available versions may be different."
        log_error "Check: ${GITLAB_URL}/${GITLAB_PROJECT_ID}/-/packages"
    fi
    exit 1
fi

log_info "Download complete: $(du -h "${TMP_DIR}/${PACKAGE_FILE}" | cut -f1)"

# Download and verify checksums if requested
if [ "$VERIFY_CHECKSUM" = true ]; then
    log_info "Downloading checksums..."
    
    if curl -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \
            "${DOWNLOAD_URL}.sha256" \
            -o "${TMP_DIR}/${PACKAGE_FILE}.sha256" 2>/dev/null; then
        
        cd "$TMP_DIR"
        if sha256sum -c "${PACKAGE_FILE}.sha256" 2>/dev/null; then
            log_info "SHA256 checksum verified ✓"
        else
            log_error "SHA256 checksum verification failed!"
            exit 1
        fi
        cd - > /dev/null
    else
        log_warn "No SHA256 checksum available"
    fi
fi

# Install or just download
if [ "$DOWNLOAD_ONLY" = true ]; then
    cp "${TMP_DIR}/${PACKAGE_FILE}" .
    log_info "Package downloaded to: $(pwd)/${PACKAGE_FILE}"
    log_info "To install, run: sudo apt install ./${PACKAGE_FILE}"
else
    log_info "Installing package..."
    
    # Check dependencies
    if ! dpkg -l | grep -q libseccomp2; then
        log_warn "libseccomp2 not installed, it will be installed as a dependency"
    fi
    
    # Install with apt (handles dependencies)
    if apt install -y "${TMP_DIR}/${PACKAGE_FILE}"; then
        log_info "Installation complete!"
        echo ""
        echo -e "${BLUE}Installed binaries:${NC}"
        echo "  /usr/local/bin/bypass4netns"
        echo "  /usr/local/bin/bypass4netnsd"
        echo ""
        echo -e "${BLUE}Documentation:${NC}"
        echo "  /usr/share/doc/bypass4netns/README.md"
        echo ""
        echo -e "${BLUE}Verify installation:${NC}"
        echo "  bypass4netns --version"
        echo ""
        
        # Show version
        if command -v bypass4netns >/dev/null 2>&1; then
            echo -e "${BLUE}Installed version:${NC}"
            bypass4netns --version
        fi
    else
        log_error "Installation failed"
        log_error "Package is saved at: ${TMP_DIR}/${PACKAGE_FILE}"
        log_error "Try manual installation: sudo dpkg -i ${TMP_DIR}/${PACKAGE_FILE}"
        exit 1
    fi
fi
