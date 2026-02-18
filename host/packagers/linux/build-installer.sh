#!/bin/bash
# ════════════════════════════════════════════════════════════════════════
#  SignBridge — Linux Installer Builder (.deb + .rpm)
#
#  Packages the PyInstaller one-dir build into both .deb and .rpm
#  installers using fpm, which:
#    - Installs SignBridge to /opt/signbridge/
#    - Registers native messaging host for Chrome, Edge, Brave, Firefox
#    - Cleans up manifests on removal
#
#  Prerequisites:
#    1. Build the host first:  host/build_linux.sh
#    2. Install fpm:
#         sudo apt install ruby-dev build-essential rpm
#         sudo gem install fpm
#
#  Usage:
#    ./build-installer.sh              # build both .deb and .rpm
#    ./build-installer.sh --deb        # build .deb only
#    ./build-installer.sh --rpm        # build .rpm only
#
#  Output: host/installers/linux/signbridge_X.Y.Z_amd64.{deb,rpm}
# ════════════════════════════════════════════════════════════════════════

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$HOST_DIR"

# ─── Configuration ──────────────────────────────────────────────────────
APP_NAME="signbridge"
APP_VERSION="1.0.0"
APP_DESCRIPTION="SignBridge — Generic Web HSM Signing Native Host"
APP_URL="https://github.com/ASE-Bucuresti/SignBridge"
MAINTAINER="ASE <signbridge@ase.ro>"
LICENSE="MIT"

INSTALL_DIR="/opt/signbridge"
EXE_NAME="SignBridge"

# Paths
DIST_DIR="$HOST_DIR/dist/SignBridge"
STAGING_DIR="$HOST_DIR/packagers/linux/_staging"
SCRIPTS_DIR="$HOST_DIR/packagers/linux/scripts"
OUTPUT_DIR="$HOST_DIR/installers/linux"

# ─── Parse arguments ───────────────────────────────────────────────────
BUILD_DEB=true
BUILD_RPM=true
if [[ "${1:-}" == "--deb" ]]; then
    BUILD_RPM=false
elif [[ "${1:-}" == "--rpm" ]]; then
    BUILD_DEB=false
fi

echo "========================================"
echo " SignBridge - Installer Build (Linux)"
echo "========================================"
echo "Formats: $(${BUILD_DEB} && echo -n '.deb ')$(${BUILD_RPM} && echo -n '.rpm')"
echo

# ─── Check fpm is installed ────────────────────────────────────────────
if ! command -v fpm &>/dev/null; then
    echo "ERROR: fpm is not installed."
    echo
    echo "Install it with:"
    echo "  sudo apt install ruby-dev build-essential rpm"
    echo "  sudo gem install fpm"
    echo
    echo "Or see: https://fpm.readthedocs.io/en/latest/installing.html"
    exit 1
fi

# ─── Check for rpmbuild if building .rpm ────────────────────────────────
if $BUILD_RPM && ! command -v rpmbuild &>/dev/null; then
    echo "WARNING: rpmbuild not found. Install 'rpm' package: sudo apt install rpm"
    echo "Skipping .rpm build."
    BUILD_RPM=false
fi

# ─── Verify PyInstaller build exists ────────────────────────────────────
if [ ! -f "$DIST_DIR/$EXE_NAME" ]; then
    echo "ERROR: dist/SignBridge/$EXE_NAME not found."
    echo "Run build_linux.sh first to build the native host."
    exit 1
fi
echo "[1/4] PyInstaller build found."

# ─── Build the staging directory ────────────────────────────────────────
echo "[2/4] Preparing installer payload..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR${INSTALL_DIR}"
mkdir -p "$OUTPUT_DIR"

# Copy the entire PyInstaller bundle into the payload
cp -R "$DIST_DIR/." "$STAGING_DIR${INSTALL_DIR}/"

# Ensure executable permission
chmod +x "$STAGING_DIR${INSTALL_DIR}/$EXE_NAME"

# ─── Common fpm arguments ──────────────────────────────────────────────
FPM_COMMON=(
    --name "$APP_NAME"
    --version "$APP_VERSION"
    --description "$APP_DESCRIPTION"
    --url "$APP_URL"
    --maintainer "$MAINTAINER"
    --license "$LICENSE"
    --architecture "amd64"
    --category "utils"

    # Scripts
    --after-install  "$SCRIPTS_DIR/postinstall"
    --before-remove  "$SCRIPTS_DIR/preremove"

    # Input
    --input-type dir
    --chdir "$STAGING_DIR"

    # Force overwrite
    --force

    # Map staging root to filesystem root
    .
)

# ─── Build .deb ─────────────────────────────────────────────────────────
if $BUILD_DEB; then
    echo "[3/4] Building .deb package..."
    fpm \
        --output-type deb \
        --package "$OUTPUT_DIR/${APP_NAME}_${APP_VERSION}_amd64.deb" \
        --depends "libxcb1" \
        "${FPM_COMMON[@]}"
    echo "  ✓ .deb package created."
else
    echo "[3/4] Skipping .deb build."
fi

# ─── Build .rpm ─────────────────────────────────────────────────────────
if $BUILD_RPM; then
    echo "[4/4] Building .rpm package..."
    fpm \
        --output-type rpm \
        --package "$OUTPUT_DIR/${APP_NAME}-${APP_VERSION}-1.x86_64.rpm" \
        --depends "libxcb" \
        "${FPM_COMMON[@]}"
    echo "  ✓ .rpm package created."
else
    echo "[4/4] Skipping .rpm build."
fi

# ─── Cleanup staging ───────────────────────────────────────────────────
rm -rf "$STAGING_DIR"

echo
echo "========================================"
echo " INSTALLER BUILD SUCCESSFUL"
echo "========================================"
echo "Output directory: $OUTPUT_DIR"
$BUILD_DEB && echo "  .deb: ${APP_NAME}_${APP_VERSION}_amd64.deb"
$BUILD_RPM && echo "  .rpm: ${APP_NAME}-${APP_VERSION}-1.x86_64.rpm"
echo
echo "Install with:"
$BUILD_DEB && echo "  sudo dpkg -i $OUTPUT_DIR/${APP_NAME}_${APP_VERSION}_amd64.deb"
$BUILD_RPM && echo "  sudo rpm -i $OUTPUT_DIR/${APP_NAME}-${APP_VERSION}-1.x86_64.rpm"
echo
