#!/bin/bash
# ════════════════════════════════════════════════════════════════════════
#  SignBridge — macOS Build Script
#  Builds a one-dir PyInstaller bundle in dist/SignBridge/
# ════════════════════════════════════════════════════════════════════════

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================"
echo " SignBridge - Production Build (macOS)"
echo "========================================"
echo

# ── Check Python ────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "ERROR: Python 3 is not installed"
    echo "Install via: brew install python3  or  xcode-select --install"
    exit 1
fi

echo "[1/7] Python version:"
python3 --version

# ── Virtual environment ─────────────────────────────────────────────────
if [ ! -d "venv" ]; then
    echo "[2/7] Creating virtual environment..."
    python3 -m venv venv
else
    echo "[2/7] Using existing virtual environment..."
fi

echo "[3/7] Activating virtual environment..."
source venv/bin/activate

# ── Install dependencies ────────────────────────────────────────────────
echo "[4/7] Installing dependencies..."
pip install --upgrade pip wheel setuptools
pip install -r requirements.txt

# ── Verify PKCS#11 library ──────────────────────────────────────────────
DYLIB="libs/libeToken.dylib"
echo "[5/7] Checking PKCS#11 library..."
if [ -f "$DYLIB" ]; then
    echo "Found: $DYLIB"
    # Remove quarantine attribute
    xattr -r -d com.apple.quarantine "$DYLIB" 2>/dev/null || true
else
    echo "WARNING: $DYLIB not found"
    echo "HSM operations will require the vendor library at runtime"
fi

# ── Clean previous build ───────────────────────────────────────────────
echo "[6/7] Cleaning previous builds..."
rm -rf dist build

# ── Build ───────────────────────────────────────────────────────────────
echo "[7/7] Building with PyInstaller..."
echo
pyinstaller --clean signbridge.spec

BIN="dist/SignBridge/SignBridge"
if [ -f "$BIN" ]; then
    echo
    echo "Removing quarantine from dist..."
    xattr -r -d com.apple.quarantine dist 2>/dev/null || true

    echo "Ad-hoc code signing..."
    # Sign all binaries
    find "dist/SignBridge" -type f \( -name "*.dylib" -o -name "*.so" -o -perm -111 \) -print0 |
        while IFS= read -r -d '' bin; do
            codesign --remove-signature "$bin" 2>/dev/null || true
            codesign --force --sign - "$bin" 2>/dev/null || true
        done
    codesign --force --deep --sign - "$BIN" 2>/dev/null || true

    echo
    echo "========================================"
    echo " BUILD SUCCESSFUL"
    echo "========================================"
    echo "Executable: $BIN"
    echo
    echo "Next steps:"
    echo "  1. python3 install/register_host.py"
    echo "  2. Load the extension in Chrome/Firefox/Edge"
    echo "  3. Test from the web app"
else
    echo
    echo "========================================"
    echo " BUILD FAILED"
    echo "========================================"
    exit 1
fi
