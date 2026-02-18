#!/bin/bash
# ════════════════════════════════════════════════════════════════════════
#  SignBridge — Linux Build Script
#  Builds a one-dir PyInstaller bundle in dist/SignBridge/
# ════════════════════════════════════════════════════════════════════════

set -euo pipefail

echo "========================================"
echo " SignBridge - Production Build (Linux)"
echo "========================================"
echo

# ── Check Python ────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "ERROR: Python 3 is not installed"
    echo "Install: sudo apt install python3 python3-venv python3-pip"
    exit 1
fi

echo "[1/5] Python version:"
python3 --version

# ── Virtual environment ─────────────────────────────────────────────────
if [ ! -f "venv/bin/activate" ]; then
    echo "[2/5] Creating virtual environment..."
    rm -rf venv
    python3 -m venv venv
else
    echo "[2/5] Using existing virtual environment..."
fi

echo "[3/5] Activating virtual environment..."
source venv/bin/activate

# ── Install dependencies ────────────────────────────────────────────────
echo "[4/5] Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# ── Verify PKCS#11 library ──────────────────────────────────────────────
if [ ! -f "libs/libeTPkcs11.so" ]; then
    echo "WARNING: libs/libeTPkcs11.so not found"
    echo "HSM operations will require the vendor library at runtime"
fi

# ── Clean previous build ───────────────────────────────────────────────
rm -rf dist build

# ── Build ───────────────────────────────────────────────────────────────
echo "[5/5] Building with PyInstaller..."
echo
pyinstaller --clean signbridge.spec

BIN="dist/SignBridge/SignBridge"
if [ -f "$BIN" ]; then
    chmod +x "$BIN"
    echo
    echo "========================================"
    echo " BUILD SUCCESSFUL"
    echo "========================================"
    echo "Executable: $BIN"
    echo "Size: $(stat -c%s "$BIN" 2>/dev/null || stat -f%z "$BIN" 2>/dev/null) bytes"
    echo
    echo "Next steps:"
    echo "  1. python3 install/register_host.py"
    echo "  2. Load the extension in Chrome/Firefox"
    echo "  3. Test from the web app"
else
    echo
    echo "========================================"
    echo " BUILD FAILED"
    echo "========================================"
    exit 1
fi
