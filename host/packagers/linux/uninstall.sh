#!/bin/bash
# ════════════════════════════════════════════════════════════════════════
#  SignBridge — Linux Uninstall Script
#
#  Standalone uninstaller for users who installed manually or want
#  a one-command uninstall. For package-managed installs, prefer:
#    sudo apt remove signbridge        (Debian/Ubuntu)
#    sudo dnf remove signbridge        (Fedora/RHEL)
#
#  Usage:  sudo /opt/signbridge/uninstall.sh
# ════════════════════════════════════════════════════════════════════════

set -euo pipefail

HOST_NAME="com.ase.signer"
APP_NAME="signbridge"
INSTALL_DIR="/opt/signbridge"

echo "========================================"
echo " SignBridge - Uninstaller (Linux)"
echo "========================================"
echo

# ─── Check root ─────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo)."
    exit 1
fi

# ─── Try package manager removal first ──────────────────────────────────
if dpkg -s "$APP_NAME" &>/dev/null 2>&1; then
    echo "Package is managed by dpkg. Using apt to remove..."
    apt remove -y "$APP_NAME"
    echo
    echo "========================================"
    echo " Uninstall complete (via apt)"
    echo "========================================"
    echo "Restart any open browsers for changes to take effect."
    exit 0
fi

if rpm -q "$APP_NAME" &>/dev/null 2>&1; then
    echo "Package is managed by rpm. Using package manager to remove..."
    if command -v dnf &>/dev/null; then
        dnf remove -y "$APP_NAME"
    elif command -v yum &>/dev/null; then
        yum remove -y "$APP_NAME"
    else
        rpm -e "$APP_NAME"
    fi
    echo
    echo "========================================"
    echo " Uninstall complete (via rpm)"
    echo "========================================"
    echo "Restart any open browsers for changes to take effect."
    exit 0
fi

# ─── Manual removal (not installed via package manager) ─────────────────
echo "No package manager entry found. Performing manual removal..."
echo

# Remove native messaging manifests
echo "Removing native messaging registrations..."

remove_for_user() {
    local user_home="$1"

    local MANIFEST_DIRS=(
        "${user_home}/.config/google-chrome/NativeMessagingHosts"
        "${user_home}/.config/chromium/NativeMessagingHosts"
        "${user_home}/.config/microsoft-edge/NativeMessagingHosts"
        "${user_home}/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts"
        "${user_home}/.mozilla/native-messaging-hosts"
    )

    for dir in "${MANIFEST_DIRS[@]}"; do
        local manifest="${dir}/${HOST_NAME}.json"
        if [ -f "$manifest" ]; then
            rm -f "$manifest"
            echo "  ✓ Removed: $manifest"
        fi
    done
}

while IFS=: read -r username _ uid _ _ home shell; do
    if [ "$uid" -ge 1000 ] && [ -d "$home" ] && \
       [[ "$shell" != */nologin ]] && [[ "$shell" != */false ]]; then
        remove_for_user "$home"
    fi
done < /etc/passwd

# Also clean up root
if [ -d "/root" ]; then
    remove_for_user "/root"
fi

# Remove application directory
echo "Removing application..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "  ✓ Removed: $INSTALL_DIR"
fi

echo
echo "========================================"
echo " Uninstall complete"
echo "========================================"
echo
echo "Restart any open browsers for changes to take effect."
