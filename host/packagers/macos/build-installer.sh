#!/bin/bash
# ════════════════════════════════════════════════════════════════════════
#  SignBridge — macOS Installer Builder (.pkg)
#
#  Packages the PyInstaller one-dir build into a signed & notarized
#  macOS .pkg installer that:
#    - Installs SignBridge to /Applications/SignBridge/
#    - Registers native messaging host for Chrome, Edge, Brave, Firefox
#    - Unregisters on removal (via uninstall script)
#
#  Prerequisites:
#    1. Build the host first:  host/build_macos.sh
#    2. Apple Developer ID (for signing & notarization)
#
#  Usage:
#    ./build-installer.sh                          # unsigned (dev/testing)
#    ./build-installer.sh --sign                   # signed + notarized
#
#  Environment variables for signing (set these or export before running):
#    DEVELOPER_ID_APP     — "Developer ID Application: Name (TEAMID)"
#    DEVELOPER_ID_INST    — "Developer ID Installer: Name (TEAMID)"
#    APPLE_TEAM_ID        — 10-char team ID
#
#  Notarization credentials (pick ONE):
#    NOTARY_PROFILE       — keychain profile from:
#                           xcrun notarytool store-credentials "SignBridge-notary"
#    — or —
#    APPLE_ID             — your Apple ID email
#    APP_PASSWORD         — app-specific password (appleid.apple.com → App-Specific Passwords)
#
#  Output: host/installers/macos/SignBridge-X.Y.Z.pkg
# ════════════════════════════════════════════════════════════════════════

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$HOST_DIR"

# ─── Configuration ──────────────────────────────────────────────────────
APP_NAME="SignBridge"
APP_VERSION="1.0.0"
BUNDLE_ID="com.ase.signbridge"
HOST_NAME="com.ase.signer"
CHROME_EXT_ID="hjfiglgfjnfceahiccedeimkgabclkpc"
FIREFOX_EXT_ID="signbridge@ase.ro"
INSTALL_DIR="/Applications/${APP_NAME}"

# Paths
DIST_DIR="$HOST_DIR/dist/SignBridge"
STAGING_DIR="$HOST_DIR/packagers/macos/_staging"
SCRIPTS_DIR="$HOST_DIR/packagers/macos/scripts"
OUTPUT_DIR="$HOST_DIR/installers/macos"
COMPONENT_PKG="$STAGING_DIR/component.pkg"
FINAL_PKG="$OUTPUT_DIR/${APP_NAME}-${APP_VERSION}.pkg"

# Signing
SIGN_MODE="unsigned"
if [[ "${1:-}" == "--sign" ]]; then
    SIGN_MODE="signed"
fi

ENTITLEMENTS="$SCRIPT_DIR/SignBridge.entitlements"

echo "========================================"
echo " SignBridge - Installer Build (macOS)"
echo "========================================"
echo "Mode: $SIGN_MODE"
echo

# ─── Verify PyInstaller build exists ────────────────────────────────────
if [ ! -f "$DIST_DIR/SignBridge" ]; then
    echo "ERROR: dist/SignBridge/SignBridge not found."
    echo "Run build_macos.sh first to build the native host."
    exit 1
fi
echo "[1/5] PyInstaller build found."

# ─── Code-sign the app bundle (if signing) ──────────────────────────────
if [ "$SIGN_MODE" == "signed" ]; then
    echo "[2/5] Code-signing binaries with Developer ID..."

    : "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP to your 'Developer ID Application: ...' identity}"
    : "${DEVELOPER_ID_INST:?Set DEVELOPER_ID_INST to your 'Developer ID Installer: ...' identity}"

    if [ ! -f "$ENTITLEMENTS" ]; then
        echo "ERROR: Missing entitlements file: $ENTITLEMENTS"
        exit 1
    fi

    # Sign nested Mach-O libs first, then the main executable (inside-out).
    # Nested libs get hardened runtime; the main binary also gets entitlements
    # so third-party PKCS#11 dylibs (different Team ID) can be dlopen()'d.
    find "$DIST_DIR" -type f \( -name "*.dylib" -o -name "*.so" -o -perm -111 \) -print0 |
        while IFS= read -r -d '' bin; do
            # Skip non-Mach-O files that happen to be executable (scripts).
            file "$bin" | grep -q 'Mach-O' || continue
            [[ "$(basename "$bin")" == "SignBridge" ]] && continue
            codesign --force --options runtime --timestamp \
                --sign "$DEVELOPER_ID_APP" "$bin"
        done

    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$DEVELOPER_ID_APP" "$DIST_DIR/SignBridge"

    codesign --verify --verbose=2 "$DIST_DIR/SignBridge"
    codesign -d --entitlements :- "$DIST_DIR/SignBridge" 2>/dev/null | grep -q disable-library-validation \
        && echo "  Entitlements OK (disable-library-validation present)." \
        || echo "  WARNING: disable-library-validation entitlement not found on binary."
    echo "  Code-signing complete."
else
    echo "[2/5] Skipping code-signing (unsigned mode)."
fi

# ─── Build the payload ──────────────────────────────────────────────────
echo "[3/5] Preparing installer payload..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/payload${INSTALL_DIR}"
mkdir -p "$OUTPUT_DIR"

# Copy the entire PyInstaller bundle into the payload
cp -R "$DIST_DIR/" "$STAGING_DIR/payload${INSTALL_DIR}/"

# Bundle the uninstall script
cp "$SCRIPT_DIR/uninstall.sh" "$STAGING_DIR/payload${INSTALL_DIR}/uninstall.sh"

# Ensure executable permissions
chmod +x "$STAGING_DIR/payload${INSTALL_DIR}/SignBridge"
chmod +x "$STAGING_DIR/payload${INSTALL_DIR}/uninstall.sh"

# ─── Build the .pkg ────────────────────────────────────────────────────
echo "[4/5] Building .pkg installer..."

# Build component package
pkgbuild \
    --root "$STAGING_DIR/payload" \
    --identifier "$BUNDLE_ID" \
    --version "$APP_VERSION" \
    --install-location "/" \
    --scripts "$SCRIPTS_DIR" \
    "$COMPONENT_PKG"

# Build product archive (distribution pkg) with customization
if [ "$SIGN_MODE" == "signed" ]; then
    productbuild \
        --package "$COMPONENT_PKG" \
        --identifier "$BUNDLE_ID" \
        --version "$APP_VERSION" \
        --sign "$DEVELOPER_ID_INST" \
        "$FINAL_PKG"
else
    productbuild \
        --package "$COMPONENT_PKG" \
        --identifier "$BUNDLE_ID" \
        --version "$APP_VERSION" \
        "$FINAL_PKG"
fi

# ─── Notarize (if signing) ─────────────────────────────────────────────
if [ "$SIGN_MODE" == "signed" ]; then
    echo "[5/5] Notarizing with Apple..."

    : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your 10-char team ID}"

    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$FINAL_PKG" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
    else
        : "${APPLE_ID:?Set APPLE_ID (or use NOTARY_PROFILE from store-credentials)}"
        : "${APP_PASSWORD:?Set APP_PASSWORD (or use NOTARY_PROFILE)}"
        xcrun notarytool submit "$FINAL_PKG" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait
    fi

    xcrun stapler staple "$FINAL_PKG"
    spctl --assess --type install -v "$FINAL_PKG" || true

    echo "  Notarization complete and stapled."
else
    echo "[5/5] Skipping notarization (unsigned mode)."
fi

# ─── Cleanup staging ───────────────────────────────────────────────────
rm -rf "$STAGING_DIR"

echo
echo "========================================"
echo " INSTALLER BUILD SUCCESSFUL"
echo "========================================"
echo "Output: $FINAL_PKG"
echo
if [ "$SIGN_MODE" == "unsigned" ]; then
    echo "NOTE: This .pkg is unsigned. Users will need to right-click → Open"
    echo "      or allow it in System Settings → Privacy & Security."
    echo
    echo "For a signed build:  ./build-installer.sh --sign"
fi
