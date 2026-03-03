#!/bin/bash
# create-deb.sh - Create a Debian package for bypass4netns
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

# Get version from git
VERSION=$(git describe --match 'v[0-9]*' --dirty='.m' --always --tags 2>/dev/null || echo "0.0.0")
VERSION=${VERSION#v}  # Remove leading 'v'
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
PKG_NAME="bypass4netns_${VERSION}_${ARCH}"
BUILD_DIR="debian-build/$PKG_NAME"

log_info "Creating Debian package: $PKG_NAME"

# Check if binaries exist, if not build them
if [ ! -f "bypass4netns" ] || [ ! -f "bypass4netnsd" ]; then
    log_info "Binaries not found, building..."
    make static strip
else
    log_warn "Using existing binaries. Run 'make clean && make static strip' for a fresh build."
fi

# Clean previous build
rm -rf debian-build
mkdir -p "$BUILD_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/usr/local/bin"
mkdir -p "$BUILD_DIR/usr/share/doc/bypass4netns"

# Copy binaries
log_info "Copying binaries..."
cp bypass4netns bypass4netnsd "$BUILD_DIR/usr/local/bin/"
chmod 755 "$BUILD_DIR/usr/local/bin/bypass4netns"
chmod 755 "$BUILD_DIR/usr/local/bin/bypass4netnsd"

# Copy documentation
cp README.md "$BUILD_DIR/usr/share/doc/bypass4netns/"
cp LICENSE "$BUILD_DIR/usr/share/doc/bypass4netns/"

# Get installed size (in KB)
INSTALLED_SIZE=$(du -sk "$BUILD_DIR" | cut -f1)

# Create control file
log_info "Creating control file..."
cat > "$BUILD_DIR/DEBIAN/control" << EOF
Package: bypass4netns
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH
Installed-Size: $INSTALLED_SIZE
Depends: libseccomp2 (>= 2.5.0)
Maintainer: IT Entwicklung <it-entwicklung@bangkran.de>
Description: Accelerator for rootless containers using seccomp
 bypass4netns accelerates TCP/IP communications in rootless
 containers by intercepting socket syscalls via seccomp.
 .
 This package provides:
  - bypass4netns: the main binary for accelerating container networking
  - bypass4netnsd: optional REST daemon for controlling bypass4netns
 .
 Requires kernel >= 5.9, runc >= 1.1 or crun >= 1.6, and libseccomp >= 2.5.
EOF

# Create postinst script (runs after installation)
cat > "$BUILD_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

# Ensure binaries are executable
chmod 755 /usr/local/bin/bypass4netns
chmod 755 /usr/local/bin/bypass4netnsd

echo "bypass4netns installed successfully!"
echo "Documentation: /usr/share/doc/bypass4netns/README.md"

exit 0
EOF
chmod 755 "$BUILD_DIR/DEBIAN/postinst"

# Create prerm script (runs before removal)
cat > "$BUILD_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/sh
set -e

# Stop any running bypass4netns processes
if pgrep -x "bypass4netns" > /dev/null; then
    echo "Warning: bypass4netns processes are still running"
    echo "Please stop them manually if needed"
fi

exit 0
EOF
chmod 755 "$BUILD_DIR/DEBIAN/prerm"

# Build the package
log_info "Building Debian package..."
dpkg-deb --build --root-owner-group "$BUILD_DIR" > /dev/null 2>&1

# Move package to current directory
mv "debian-build/${PKG_NAME}.deb" .

# Calculate checksums
log_info "Generating checksums..."
sha256sum "${PKG_NAME}.deb" > "${PKG_NAME}.deb.sha256"
md5sum "${PKG_NAME}.deb" > "${PKG_NAME}.deb.md5"

# Show package info
log_info "Package created successfully!"
echo ""
echo "Package file:     ${PKG_NAME}.deb"
echo "Version:          $VERSION"
echo "Architecture:     $ARCH"
echo "Size:             $(du -h "${PKG_NAME}.deb" | cut -f1)"
echo "SHA256:           $(cat "${PKG_NAME}.deb.sha256" | cut -d' ' -f1)"
echo ""
log_info "You can now install with: sudo apt install ./${PKG_NAME}.deb"
log_info "Or upload with: ./upload-package.sh ${PKG_NAME}.deb"

# Clean up build directory
rm -rf debian-build
