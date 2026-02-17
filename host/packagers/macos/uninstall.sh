#!/bin/bash
# ════════════════════════════════════════════════════════════════════════
#  SignBridge — macOS pre-uninstall / cleanup script
#
#  Standalone uninstaller since .pkg doesn't have native uninstall.
#  Run:  sudo /Applications/SignBridge/uninstall.sh
#        or include in a future update's preinstall if needed.
# ════════════════════════════════════════════════════════════════════════

set -euo pipefail

APP_NAME="SignBridge"
HOST_NAME="com.ase.signer"
BUNDLE_ID="com.ase.signbridge"

# Find the real user (we may be running via sudo)
if [ "$(id -u)" -eq 0 ]; then
    CONSOLE_USER=$(stat -f "%Su" /dev/console 2>/dev/null || echo "$USER")
    USER_HOME=$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
else
    CONSOLE_USER="$USER"
    USER_HOME="$HOME"
fi

echo "========================================"
echo " SignBridge - Uninstaller (macOS)"
echo "========================================"
echo
echo "User: $CONSOLE_USER"
echo

# ─── Remove native messaging manifests ──────────────────────────────────
echo "Removing native messaging registrations..."

MANIFEST_DIRS=(
    "${USER_HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"
    "${USER_HOME}/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
    "${USER_HOME}/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
    "${USER_HOME}/Library/Application Support/Mozilla/NativeMessagingHosts"
)

for dir in "${MANIFEST_DIRS[@]}"; do
    manifest="${dir}/${HOST_NAME}.json"
    if [ -f "$manifest" ]; then
        rm -f "$manifest"
        echo "  ✓ Removed: $manifest"
    fi
done

# ─── Remove application ────────────────────────────────────────────────
echo "Removing application..."
if [ -d "/Applications/${APP_NAME}" ]; then
    rm -rf "/Applications/${APP_NAME}"
    echo "  ✓ Removed: /Applications/${APP_NAME}"
fi

# ─── Forget the package receipt ─────────────────────────────────────────
echo "Removing package receipt..."
pkgutil --forget "$BUNDLE_ID" 2>/dev/null || true
echo "  ✓ Receipt cleared."

echo
echo "========================================"
echo " Uninstall complete"
echo "========================================"
echo
echo "Restart any open browsers for changes to take effect."
